import AppKit
import SwiftUI
import ServiceManagement

// ═══════════════════════════════════════════════════════════════
// MARK: - Single Instance Guard (flock-based)
// ═══════════════════════════════════════════════════════════════

private let instanceLockFile = URL(
    fileURLWithPath: NSTemporaryDirectory()
).appendingPathComponent("com.runcatx.lock")
nonisolated(unsafe) private var instanceLockFD: Int32 = -1 {
    didSet { _ = instanceLockFD } // suppress unused warning
}

private func isAlreadyRunning() -> Bool {
    instanceLockFD = open(instanceLockFile.path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o600)
    guard instanceLockFD >= 0 else { return true }
    let locked = flock(instanceLockFD, LOCK_EX | LOCK_NB) == 0
    if !locked { close(instanceLockFD); instanceLockFD = -1 }
    return !locked
}

/// Called on app termination to release the lock.
private func releaseInstanceLock() {
    if instanceLockFD >= 0 {
        flock(instanceLockFD, LOCK_UN)
        close(instanceLockFD)
        instanceLockFD = -1
        try? FileManager.default.removeItem(at: instanceLockFile)
    }
}

@main
struct RunCatXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1️⃣ Single instance — exit if already running
        guard !isAlreadyRunning() else {
            print("⚠️ RunCatX: another instance is already running")
            NSApplication.shared.terminate(nil)
            return
        }

        // 2️⃣ Menu bar only — no dock icon
        NSApp.setActivationPolicy(.accessory)

        // 3️⃣ Restore settings & start
        SettingsStore.shared.restore()
        statusBarController = StatusBarController()
        statusBarController?.start()

        // 4️⃣ Launch at startup (if enabled)
        LaunchAtStartup.apply(SettingsStore.shared.launchAtStartup)

        // 5️⃣ Sleep/Wake observers (pause animation on sleep)
        NCAddObserver(name: NSWorkspace.willSleepNotification,   selector: #selector(handleSleep))
        NCAddObserver(name: NSWorkspace.didWakeNotification,     selector: #selector(handleWake))
        NCAddObserver(name: NSWorkspace.screensDidSleepNotification, selector: #selector(handleSleep))

        // 6️⃣ Register for termination cleanup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        handleTerminate()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Sleep / Wake

    @objc private func handleSleep() {
        statusBarController?.pause()
    }

    @objc private func handleWake() {
        statusBarController?.resume()
    }

    @objc private func handleTerminate() {
        statusBarController?.stop()
        releaseInstanceLock()
    }

    /// Convenience for workspace notification center observers.
    private func NCAddObserver(name: Notification.Name, selector: Selector) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: selector, name: name, object: nil
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Launch At Startup (macOS 13+ SMAppService)
// ═══════════════════════════════════════════════════════════════

enum LaunchAtStartup {
    static func apply(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("⚠️ RunCatX: failed to set launch at startup: \(error)")
            }
        } else {
            setLoginItemLegacy(enabled)
        }
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else { return isLoginItemEnabledLegacy }
    }

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.runcatx"

    private static func setLoginItemLegacy(_ enabled: Bool) {
        SMLoginItemSetEnabled(bundleID as CFString, enabled)
    }

    private static var isLoginItemEnabledLegacy: Bool {
        if let items = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]] {
            return items.contains { ($0["Label"] as? String) == bundleID }
        }
        return false
    }
}

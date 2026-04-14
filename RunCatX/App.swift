import AppKit
import SwiftUI
import ServiceManagement
import Darwin

// ═══════════════════════════════════════════════════════════════
// MARK: - Dev Mode Self-Reload (--dev flag)
// ═══════════════════════════════════════════════════════════════
//
// When launched with --dev, RunCatX watches its own binary's mtime.
// When fswatch+swift-build produces a newer binary, the app calls
// execv() to replace itself in-place — instant, no kill+open gap.
//
// Usage:  .build/debug/RunCatX --dev
//         (dev.sh handles this automatically)
//

nonisolated(unsafe) private var devModeReloadTimer: Timer?
nonisolated(unsafe) private var devModeLastModTime: TimeInterval = 0

/// Check if --dev was passed as a CLI argument.
private func isDevMode() -> Bool {
    CommandLine.arguments.contains("--dev")
}

/// Start watching own binary for changes (dev mode only).
private func startDevModeWatch() {
    guard let path = Bundle.main.executablePath else { return }
    let fm = FileManager.default

    // Seed initial mtime
    if let attrs = try? fm.attributesOfItem(atPath: path),
       let mod = attrs[.modificationDate] as? Date {
        devModeLastModTime = mod.timeIntervalSince1970
    }

    devModeReloadTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let mod = attrs[.modificationDate] as? Date else { return }

        let newTime = mod.timeIntervalSince1970
        guard newTime > devModeLastModTime + 0.01 else { return }  // ignore sub-ms noise

        print("🔥 Dev reload detected (binary updated)")
        devModeLastModTime = newTime

        // Stop everything cleanly before execv
        devModeReloadTimer?.invalidate()
        devModeReloadTimer = nil

        // Notify via NotificationCenter so AppDelegate can clean up
        NotificationCenter.default.post(name: .init("DevModeWillReload"), object: nil)

        // Small delay to allow cleanup to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            performSelfReload(execPath: path)
        }
    }
}

/// Replace current process with a fresh instance of the same binary.
/// Uses execv() — same PID slot, instant replacement, no dock flash.
private func performSelfReload(execPath: String) {
    // Release the instance lock so the new process can acquire it
    releaseInstanceLock()

    let argv = CommandLine.unsafeArgv
    // execv replaces the process image; only reaches here on failure
    execv(execPath, argv)
    // If execv fails, fall back to exit (shouldn't happen)
    fatalError("RunCatX: execv failed: \(String(cString: strerror(errno)))")
}

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
        let dev = isDevMode()

        // 1️⃣ Single instance — exit if already running (unless --dev reload)
        if isAlreadyRunning() {
            if dev {
                // Dev mode: previous instance is about to execv and release lock
                Thread.sleep(forTimeInterval: 0.5)
                if isAlreadyRunning() {
                    // Still locked after waiting — truly another instance
                    print("⚠️ RunCatX: another instance is still running")
                    NSApplication.shared.terminate(nil)
                    return
                }
                // Lock released — we can proceed
            } else {
                print("⚠️ RunCatX: another instance is already running")
                NSApplication.shared.terminate(nil)
                return
            }
        }

        // 2️⃣ Menu bar only — no dock icon
        NSApp.setActivationPolicy(.accessory)

        // 3️⃣ Restore settings & start
        SettingsStore.shared.restore()
        statusBarController = StatusBarController()
        statusBarController?.start()

        // 4️⃣ Launch at startup (skip in dev mode)
        if !dev {
            LaunchAtStartup.apply(SettingsStore.shared.launchAtStartup)
        }

        // 5️⃣ Sleep/Wake observers (pause animation on sleep)
        NCAddObserver(name: NSWorkspace.willSleepNotification,   selector: #selector(handleSleep))
        NCAddObserver(name: NSWorkspace.didWakeNotification,     selector: #selector(handleWake))
        NCAddObserver(name: NSWorkspace.screensDidSleepNotification, selector: #selector(handleSleep))

        // 6️⃣ Register for termination cleanup + dev reload
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        // 7️⃣ Dev mode: watch own binary for changes → auto execv
        if dev {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleDevReload),
                name: .init("DevModeWillReload"),
                object: nil
            )
            startDevModeWatch()
            print("🔥 RunCatX: dev mode active (self-reload on binary change)")
        }
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

    /// Dev mode: clean up before execv self-reload.
    @objc private func handleDevReload() {
        print("🔄 RunCatX: cleaning up for dev reload...")
        statusBarController?.stop()
        // Don't release lock here — performSelfReload does it
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

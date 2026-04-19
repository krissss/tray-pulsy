import ServiceManagement
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Single Instance Guard (flock-based)
// ═══════════════════════════════════════════════════════════════

private let instanceLockFile = URL(
    fileURLWithPath: NSTemporaryDirectory()
).appendingPathComponent("com.traypulsy.lock")

nonisolated(unsafe) private var instanceLockFD: Int32 = -1

/// Acquire an exclusive flock. Returns `true` if we are the sole instance.
private func acquireInstanceLock() -> Bool {
    instanceLockFD = open(instanceLockFile.path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o644)
    guard instanceLockFD >= 0 else { return false }
    let ok = flock(instanceLockFD, LOCK_EX | LOCK_NB) == 0
    if !ok { close(instanceLockFD); instanceLockFD = -1 }
    return ok
}

private func releaseInstanceLock() {
    if instanceLockFD >= 0 {
        flock(instanceLockFD, LOCK_UN)
        close(instanceLockFD)
        instanceLockFD = -1
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - App Entry Point
// ═══════════════════════════════════════════════════════════════

@main
struct TrayPulsyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── 1️⃣ Single instance guard ──
        if !acquireInstanceLock() {
            print("⚠️ \(AppConstants.appName) is already running")
            exit(0)
        }

        // ── 2️⃣ Hide Dock icon & menu bar presence ──
        NSApp.setActivationPolicy(.accessory)

        // ── 3️⃣ Create status bar item + start animation ──
        statusBarController = StatusBarController()
        statusBarController?.start()

        // ── 4️⃣ Register for launch-at-login ──
        _ = SMAppService.mainApp

        // ── 5️⃣ Handle sleep/wake to pause/resume animation ──
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseInstanceLock()
    }

    @objc private func handleSleep() {
        statusBarController?.pause()
    }

    @objc private func handleWake() {
        statusBarController?.resume()
    }
}

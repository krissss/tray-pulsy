import AppKit
import SwiftUI
import XCTest
@testable import TrayPulsy

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsWindowLayoutHasFiniteFittingSize() {
        let updateManager = AppUpdateManager()
        let appState = AppState(
            systemMonitor: SystemMonitor(),
            skinManager: SkinManager(),
            updateManager: updateManager
        )
        let hostingView = NSHostingView(rootView: SettingsView().environment(appState))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        XCTAssertTrue(fittingSize.width.isFinite)
        XCTAssertTrue(fittingSize.height.isFinite)
        XCTAssertLessThan(fittingSize.width, 5_000)
        XCTAssertLessThan(fittingSize.height, 5_000)

        window.contentView = nil
    }
}

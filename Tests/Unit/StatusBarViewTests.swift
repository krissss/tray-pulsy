import AppKit
import XCTest
@testable import TrayPulsy

/// Covers the menu-bar text color contract, which had no test coverage while the
/// `colors` / threshold path was reworked:
/// - the user-selected color must reach BOTH the label and the value strings
/// - a threshold override must change only the value it belongs to
/// - an unchanged tick must not rebuild anything (per-tick allocation guard)
@MainActor
final class StatusBarViewTests: XCTestCase {

    func testTextColorAppliesToLabelsAndValues() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems([.cpu, .memory], sampleValues: ["12%", "34%"], valueOverrideColors: [nil, nil])

        let colors = view.renderedForegroundColors
        XCTAssertEqual(colors.labels, [.systemRed, .systemRed])
        XCTAssertEqual(colors.values, [.systemRed, .systemRed])
    }

    func testThresholdOverrideTouchesOnlyItsOwnValue() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems(
            [.cpu, .memory],
            sampleValues: ["12%", "98%"],
            valueOverrideColors: [nil, .systemYellow]
        )

        let colors = view.renderedForegroundColors
        // Labels never take threshold colors.
        XCTAssertEqual(colors.labels, [.systemRed, .systemRed])
        // Only the over-threshold column changes; the in-range one keeps the base color.
        XCTAssertEqual(colors.values, [.systemRed, .systemYellow])
    }

    func testUnchangedTickDoesNotInvalidateDisplay() {
        // needsDisplay is only tracked once the view belongs to a window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let view = StatusBarView()
        window.contentView = view

        view.setItems([.cpu], sampleValues: ["12%"], valueOverrideColors: [nil])

        // Force a display pass so the pending-invalidation flag is cleared; then a tick
        // with identical values must not set it again.
        view.display()
        XCTAssertFalse(view.needsDisplay, "precondition: display() clears the invalidation flag")

        view.updateValues(["12%"], valueOverrideColors: [nil])
        XCTAssertFalse(view.needsDisplay, "identical values + overrides must not trigger a redraw")

        view.updateValues(["13%"], valueOverrideColors: [nil])
        XCTAssertTrue(view.needsDisplay, "a changed value must trigger a redraw")
    }

    /// A value can cross a threshold while formatting to the same string (79.6% → 80.4%
    /// both render as "80%"). The color must still update in that case.
    func testThresholdCrossingWithIdenticalTextStillRepaints() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems([.cpu], sampleValues: ["80%"], valueOverrideColors: [nil])
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemRed])

        view.updateValues(["80%"], valueOverrideColors: [.systemYellow])
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemYellow])
    }

    func testClearDropsOverridesSoTheyDoNotResurrect() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems([.cpu], sampleValues: ["1%"], valueOverrideColors: [.systemYellow])
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemYellow])

        view.clear()
        XCTAssertTrue(view.renderedForegroundColors.labels.isEmpty)
        XCTAssertTrue(view.renderedForegroundColors.values.isEmpty)

        view.setItems([.cpu], sampleValues: ["1%"], valueOverrideColors: [nil])
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemRed],
                       "after clear() the old threshold override must not come back")
    }

    func testSetItemsWithSameItemsButNewOverrideStillUpdatesColors() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems([.cpu], sampleValues: ["80%"], valueOverrideColors: [nil])
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemRed])

        // Same item set, threshold crossed: the guard must not swallow it.
        view.setItems([.cpu], sampleValues: ["80%"], valueOverrideColors: [.systemYellow])
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemYellow])
    }

    func testSetTextColorRepaintsExistingValues() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems([.cpu], sampleValues: ["12%"], valueOverrideColors: [nil])

        view.setTextColor(.systemBlue)
        let colors = view.renderedForegroundColors
        XCTAssertEqual(colors.labels, [.systemBlue])
        XCTAssertEqual(colors.values, [.systemBlue])
    }
}

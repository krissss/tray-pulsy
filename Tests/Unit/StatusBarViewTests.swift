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

    /// `nil` = 跟随系统：必须回落到动态色 `labelColor`，而不是某个固定色。
    func testNilTextColorFallsBackToDynamicLabelColor() {
        let view = StatusBarView()
        view.setTextColor(.systemRed)
        view.setItems([.cpu], sampleValues: ["12%"], valueOverrideColors: [nil])

        view.setTextColor(nil)

        let colors = view.renderedForegroundColors
        XCTAssertEqual(colors.labels, [.labelColor])
        XCTAssertEqual(colors.values, [.labelColor])
    }

    /// 阈值覆盖仍然只改自己那一列，不受「跟随系统」影响。
    func testThresholdOverrideStillAppliesWhileFollowingSystem() {
        let view = StatusBarView()
        view.setTextColor(nil)
        view.setItems(
            [.cpu, .memory],
            sampleValues: ["12%", "98%"],
            valueOverrideColors: [nil, .systemYellow]
        )

        let colors = view.renderedForegroundColors
        XCTAssertEqual(colors.labels, [.labelColor, .labelColor])
        XCTAssertEqual(colors.values, [.labelColor, .systemYellow])
    }

    // MARK: - 菜单栏外观（「跟随系统」的真实链路）

    /// 文字必须和相邻菜单栏图标同色，靠的是「动态色 + 按所在外观解析」，而**不是**任何
    /// 硬编码的深浅色判断。这条走完整链路：窗口 appearance → 视图 effectiveAppearance →
    /// 绘制时解析出的实际亮度。系统给的是暗色菜单栏（壁纸偏暗）时文字就该是白的。
    func testFollowSystemColorResolvesAgainstItsHostingAppearance() {
        let window = makeWindow()
        let view = StatusBarView()
        window.contentView = view
        view.setTextColor(nil)
        view.setItems([.cpu], sampleValues: ["12%"], valueOverrideColors: [nil])

        window.appearance = NSAppearance(named: .vibrantDark)
        XCTAssertGreaterThan(resolvedBrightness(of: view), 0.5,
                             "深色菜单栏下文字应为浅色，才能和白色图标同色")
        window.appearance = NSAppearance(named: .vibrantLight)
        XCTAssertLessThan(resolvedBrightness(of: view), 0.5,
                          "浅色菜单栏下文字应为深色")
    }

    /// 反过来：主动选了颜色就不该再随菜单栏外观变——固定色是用户的显式选择。
    func testCustomColorIgnoresMenuBarAppearance() {
        let window = makeWindow()
        let view = StatusBarView()
        window.contentView = view
        view.setTextColor(.systemPink)
        view.setItems([.cpu], sampleValues: ["12%"], valueOverrideColors: [nil])

        window.appearance = NSAppearance(named: .vibrantDark)
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemPink])
        window.appearance = NSAppearance(named: .vibrantLight)
        XCTAssertEqual(view.renderedForegroundColors.values, [.systemPink])
    }

    /// 外观变了要重绘，否则缓存的富文本会停在旧外观解析出的颜色上。
    func testAppearanceChangeInvalidatesDisplay() {
        let window = makeWindow()
        let view = StatusBarView()
        window.contentView = view
        view.setItems([.cpu], sampleValues: ["12%"], valueOverrideColors: [nil])

        // 挂窗本身会置位失效标记，先走一次真实绘制把它清掉。
        view.display()
        XCTAssertFalse(view.needsDisplay, "precondition: display() clears the invalidation flag")

        window.appearance = NSAppearance(named: .vibrantDark)
        XCTAssertTrue(view.needsDisplay, "菜单栏外观变化必须触发重绘")
    }

    // MARK: - Helpers

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    /// 视图当前外观下，绘制用的实际亮度（0 = 黑，1 = 白）。
    private func resolvedBrightness(of view: StatusBarView) -> CGFloat {
        var brightness: CGFloat = -1
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            brightness = view.renderedForegroundColors.values.first?
                .usingColorSpace(.sRGB)?.brightnessComponent ?? -1
        }
        return brightness
    }
}

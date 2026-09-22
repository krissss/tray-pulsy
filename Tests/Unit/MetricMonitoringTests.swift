import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import TrayPulsy

/// 指标 Tab 的「关闭」承诺「停止采样并隐藏指标」（`settings.metrics.footer`）。
/// 这里守住两条承诺：
/// 1. 已关闭的指标不得因为还留在悬浮窗列表里就继续被采样；
/// 2. 「关闭」不改动悬浮窗的设置——勾选保留、总开关不动，重新启用后自动恢复。
@MainActor
final class MetricMonitoringTests: XCTestCase {

    private var savedMonitorItems: Set<MetricDisplayItem> = []
    private var savedDisplayItems: Set<MetricDisplayItem> = []
    private var savedFloatingItems: Set<MetricDisplayItem> = []
    private var savedFloatingEnabled = false
    private var savedShowsSkin = false
    private var savedLayout: FloatingWindowMetricsLayout = .horizontal

    override func setUp() {
        super.setUp()
        savedMonitorItems = Defaults[.metricMonitorItems]
        savedDisplayItems = Defaults[.metricDisplayItems]
        savedFloatingItems = Defaults[.floatingWindowMetricItems]
        savedFloatingEnabled = Defaults[.floatingWindowEnabled]
        savedShowsSkin = Defaults[.floatingWindowShowsSkin]
        savedLayout = Defaults[.floatingWindowMetricsLayout]
    }

    override func tearDown() {
        Defaults[.metricMonitorItems] = savedMonitorItems
        Defaults[.metricDisplayItems] = savedDisplayItems
        Defaults[.floatingWindowMetricItems] = savedFloatingItems
        Defaults[.floatingWindowEnabled] = savedFloatingEnabled
        Defaults[.floatingWindowShowsSkin] = savedShowsSkin
        Defaults[.floatingWindowMetricsLayout] = savedLayout
        super.tearDown()
    }

    private func makeAppState() -> AppState {
        AppState(
            systemMonitor: SystemMonitor(),
            skinManager: SkinManager(),
            updateManager: AppUpdateManager()
        )
    }

    /// 悬浮窗列着 CPU，指标 Tab 把 CPU 设为「关闭」→ CPU 必须停止采样。
    func testTurningMetricOffStopsSamplingWhileFloatingWindowStillListsIt() {
        Defaults[.metricMonitorItems] = [.cpu, .memory]
        Defaults[.floatingWindowMetricItems] = [.cpu, .memory]
        Defaults[.floatingWindowEnabled] = true

        let appState = makeAppState()
        appState.updateEnabledMetrics(settingsOpen: false)
        XCTAssertTrue(
            appState.systemMonitor.enabledMetrics.contains(.cpu),
            "前置条件：CPU 处于监控中"
        )

        // 指标 Tab → CPU → 模式选「关闭」
        Defaults[.metricMonitorItems] = [.memory]
        Defaults[.metricDisplayItems] = []

        appState.updateEnabledMetrics(settingsOpen: false)
        XCTAssertFalse(
            appState.systemMonitor.enabledMetrics.contains(.cpu),
            "「关闭」必须停止采样，不能因为悬浮窗列表里还留着 CPU 就继续采集"
        )
    }

    /// 悬浮窗关闭时，悬浮窗列表不应把指标拉回采样。
    func testFloatingWindowListDoesNotResurrectSamplingWhenWindowDisabled() {
        Defaults[.metricMonitorItems] = [.memory]
        Defaults[.floatingWindowMetricItems] = [.cpu, .memory]
        Defaults[.floatingWindowEnabled] = false

        let appState = makeAppState()
        appState.updateEnabledMetrics(settingsOpen: false)
        XCTAssertFalse(appState.systemMonitor.enabledMetrics.contains(.cpu))
        XCTAssertTrue(appState.systemMonitor.enabledMetrics.contains(.memory))
    }

    // MARK: - FloatingMetricsSelection

    func testResolvedItemsKeepsOnlyMonitoredMetrics() {
        let resolved = FloatingMetricsSelection.resolvedItems(
            stored: [.cpu, .memory, .disk],
            monitored: [.cpu, .disk],
            fallbackWhenEmpty: true
        )
        XCTAssertEqual(resolved, [.cpu, .disk])
    }

    func testEmptyStoredListFallsBackToDefaultsWithinMonitored() {
        // 默认悬浮窗指标 = [.cpu, .memory, .networkDown]
        let resolved = FloatingMetricsSelection.resolvedItems(
            stored: [],
            monitored: [.cpu, .gpu],
            fallbackWhenEmpty: true
        )
        XCTAssertEqual(resolved, [.cpu])
    }

    func testDisabledFloatingWindowDoesNotApplyDefaultFallback() {
        let resolved = FloatingMetricsSelection.resolvedItems(
            stored: [],
            monitored: [.cpu],
            fallbackWhenEmpty: false
        )
        XCTAssertTrue(resolved.isEmpty)
    }

    /// 悬浮窗尺寸按「实际展示的指标」计算，未监控的项不再占位。
    func testFloatingWindowContentSizeCountsOnlyMonitoredMetrics() {
        Defaults[.floatingWindowShowsSkin] = false
        Defaults[.floatingWindowMetricsLayout] = .horizontal
        Defaults[.floatingWindowMetricItems] = [.cpu, .memory, .gpu]

        Defaults[.metricMonitorItems] = [.cpu]
        let singleItem = FloatingMetricsPanelController.contentSize()

        Defaults[.metricMonitorItems] = [.cpu, .memory, .gpu]
        let threeItems = FloatingMetricsPanelController.contentSize()

        XCTAssertGreaterThan(
            threeItems.width,
            singleItem.width,
            "未监控的指标不应占用悬浮窗宽度"
        )
    }

    // MARK: - shouldShowPanel

    func testPanelHiddenWhenWindowDisabled() {
        XCTAssertFalse(
            FloatingMetricsSelection.shouldShowPanel(
                windowEnabled: false,
                stored: [.cpu],
                monitored: [.cpu]
            )
        )
    }

    func testPanelShownWhenWindowEnabledAndItemsAreMonitored() {
        XCTAssertTrue(
            FloatingMetricsSelection.shouldShowPanel(
                windowEnabled: true,
                stored: [.cpu],
                monitored: [.cpu, .memory]
            )
        )
    }

    /// 列表里的指标全被关掉 → 面板暂时隐藏（而不是把总开关关掉）。
    func testPanelHiddenWhenEveryListedMetricIsTurnedOff() {
        XCTAssertFalse(
            FloatingMetricsSelection.shouldShowPanel(
                windowEnabled: true,
                stored: [.cpu],
                monitored: [.memory]
            )
        )
    }

    /// 空列表会回退到默认指标，不能因为「列表为空」就隐藏面板。
    func testPanelShownForEmptyListFallback() {
        XCTAssertTrue(
            FloatingMetricsSelection.shouldShowPanel(
                windowEnabled: true,
                stored: [],
                monitored: [.cpu]
            )
        )
    }

    // MARK: - 「关闭」不改动悬浮窗设置

    /// 三态选择只写「监控」与「菜单栏显示」——`MetricMonitoringPolicy.apply` 的签名里
    /// 根本没有悬浮窗参数，所以指标 Tab 不可能改动悬浮窗设置。
    func testModeChangeTouchesOnlyMonitoringAndDisplay() {
        let off = MetricMonitoringPolicy.apply(
            .off,
            to: .cpu,
            monitored: [.cpu, .memory],
            displayed: [.cpu]
        )
        XCTAssertEqual(off.monitored, [.memory], "「关闭」停止监控")
        XCTAssertEqual(off.displayed, [], "「关闭」同时从菜单栏撤下")

        let monitorOnly = MetricMonitoringPolicy.apply(
            .monitorOnly,
            to: .cpu,
            monitored: [.memory],
            displayed: [.cpu]
        )
        XCTAssertEqual(monitorOnly.monitored, [.cpu, .memory])
        XCTAssertEqual(monitorOnly.displayed, [])

        let menuBar = MetricMonitoringPolicy.apply(
            .menuBar,
            to: .cpu,
            monitored: [.memory],
            displayed: []
        )
        XCTAssertEqual(menuBar.monitored, [.cpu, .memory])
        XCTAssertEqual(menuBar.displayed, [.cpu])
    }

    /// 「关闭 → 悬浮窗暂时隐藏 → 重新启用 → 自动恢复」，全程悬浮窗设置不动。
    ///
    /// `stored` / `windowEnabled` 都是 `let`：悬浮窗那两件套从头到尾没被碰过。
    func testPanelHidesThenComesBackWithoutTouchingFloatingSettings() {
        let stored: Set<MetricDisplayItem> = [.cpu]
        let windowEnabled = true
        var monitored: Set<MetricDisplayItem> = [.cpu, .memory]
        let displayed: Set<MetricDisplayItem> = []

        XCTAssertTrue(
            panelShouldShow(windowEnabled: windowEnabled, stored: stored, monitored: monitored),
            "前置条件：CPU 已监控且在悬浮窗列表里"
        )

        // 指标 Tab → CPU → 「关闭」
        monitored = MetricMonitoringPolicy.apply(
            .off,
            to: .cpu,
            monitored: monitored,
            displayed: displayed
        ).monitored
        XCTAssertFalse(
            panelShouldShow(windowEnabled: windowEnabled, stored: stored, monitored: monitored),
            "没有可展示的指标时暂时隐藏面板（而不是关掉总开关）"
        )

        // 指标 Tab → CPU → 「仅监控」：不必去悬浮窗页重勾
        monitored = MetricMonitoringPolicy.apply(
            .monitorOnly,
            to: .cpu,
            monitored: monitored,
            displayed: displayed
        ).monitored
        XCTAssertTrue(
            panelShouldShow(windowEnabled: windowEnabled, stored: stored, monitored: monitored),
            "重新启用后悬浮窗应自动恢复"
        )
        XCTAssertEqual(
            FloatingMetricsSelection.resolvedItems(
                stored: stored,
                monitored: monitored,
                fallbackWhenEmpty: true
            ),
            [.cpu],
            "恢复后展示的仍是用户原先勾选的那一项"
        )
    }

    /// 指标 Tab 全关之后再全开，悬浮窗也应恢复。
    func testPanelRecoversAfterLastMetricIsReEnabled() {
        let stored: Set<MetricDisplayItem> = [.gpu]

        XCTAssertFalse(
            panelShouldShow(windowEnabled: true, stored: stored, monitored: [])
        )
        XCTAssertTrue(
            panelShouldShow(windowEnabled: true, stored: stored, monitored: [.gpu])
        )
    }

    // MARK: - 悬浮窗页开关的显示状态

    /// 未监控的项虽然在展示集合里被过滤掉了，开关仍要显示**被保留的勾选**；
    /// 否则用户看到的是「没勾」，与「勾选会被保留、重新启用后自动恢复」矛盾。
    func testUnmonitoredToggleShowsKeptSelection() {
        XCTAssertTrue(
            FloatingMetricsSelection.toggleState(
                for: .cpu,
                stored: [.cpu],
                monitored: [.memory],
                windowEnabled: true
            ),
            "未监控的项要显示被保留的勾选"
        )
        XCTAssertFalse(
            FloatingMetricsSelection.toggleState(
                for: .cpu,
                stored: [],
                monitored: [.memory],
                windowEnabled: true
            ),
            "没勾过就是没勾"
        )
    }

    /// 监控中的项显示「现在是否真的展示」：总开关关掉时全部显示为关（既有行为）。
    func testMonitoredToggleReflectsEffectiveState() {
        XCTAssertTrue(
            FloatingMetricsSelection.toggleState(
                for: .cpu,
                stored: [.cpu],
                monitored: [.cpu, .memory],
                windowEnabled: true
            )
        )
        XCTAssertFalse(
            FloatingMetricsSelection.toggleState(
                for: .cpu,
                stored: [.cpu],
                monitored: [.cpu, .memory],
                windowEnabled: false
            )
        )
    }

    private func panelShouldShow(
        windowEnabled: Bool,
        stored: Set<MetricDisplayItem>,
        monitored: Set<MetricDisplayItem>
    ) -> Bool {
        FloatingMetricsSelection.shouldShowPanel(
            windowEnabled: windowEnabled,
            stored: stored,
            monitored: monitored
        )
    }

    // MARK: - 悬浮窗视图接线

    /// 悬浮窗视图本身也要按「监控中」过滤——验证 SwiftUI 侧的接线，
    /// 而不只是验证策略函数（视图宽度随展示项数变化）。
    func testFloatingMetricsViewDropsUnmonitoredMetrics() {
        Defaults[.floatingWindowShowsSkin] = false
        Defaults[.floatingWindowMetricsLayout] = .horizontal
        Defaults[.floatingWindowMetricItems] = [.cpu, .memory, .gpu]

        Defaults[.metricMonitorItems] = [.cpu, .memory, .gpu]
        let threeMonitored = floatingMetricsViewWidth()

        Defaults[.metricMonitorItems] = [.cpu]
        let oneMonitored = floatingMetricsViewWidth()

        XCTAssertGreaterThan(oneMonitored, 0, "至少还应有 1 项")
        XCTAssertGreaterThan(
            threeMonitored,
            oneMonitored,
            "悬浮窗视图宽度应随实际展示的指标数量变化"
        )
    }

    private func floatingMetricsViewWidth() -> CGFloat {
        let hostingView = NSHostingView(rootView: FloatingMetricsView(
            systemMonitor: SystemMonitor(),
            skinFrameView: FloatingSkinFrameView(),
            openSettings: {},
            hideWindow: {}
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let width = hostingView.fittingSize.width
        window.contentView = nil
        return width
    }
}

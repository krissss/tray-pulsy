import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import TrayPulsy

/// 指标页每行是「监听开关 + 菜单栏/浮窗勾选框」。这里守住三条承诺：
/// 1. 开关关掉就停止采样（`settings.metrics.footer`），不被任何勾选拉回来；
/// 2. 开关关掉只禁用勾选框、不清理勾选，重新打开后自动恢复；
/// 3. 展示目标（菜单栏 / 悬浮窗）真正展示的是「勾选 ∩ 监听」，未监听的项不得显示陈旧值。
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

    private func rowSettings(
        monitored: Set<MetricDisplayItem> = [],
        displayed: Set<MetricDisplayItem> = [],
        floatingItems: Set<MetricDisplayItem> = [],
        floatingWindowEnabled: Bool = false
    ) -> MetricRowSettings {
        MetricRowSettings(
            monitored: monitored,
            displayed: displayed,
            floatingItems: floatingItems,
            floatingWindowEnabled: floatingWindowEnabled
        )
    }

    private func panelShouldShow(_ settings: MetricRowSettings) -> Bool {
        FloatingMetricsSelection.shouldShowPanel(
            windowEnabled: settings.floatingWindowEnabled,
            stored: settings.floatingItems,
            monitored: settings.monitored
        )
    }

    // MARK: - 开关关掉就停止采样

    /// 菜单栏与浮窗都还勾着 CPU，但指标页把 CPU 的监听开关关掉 → 必须停止采样。
    func testTurningMonitoringOffStopsSamplingWhileSelectionsRemain() {
        Defaults[.metricMonitorItems] = [.cpu, .memory]
        Defaults[.metricDisplayItems] = [.cpu]
        Defaults[.floatingWindowMetricItems] = [.cpu, .memory]
        Defaults[.floatingWindowEnabled] = true

        let appState = makeAppState()
        appState.updateEnabledMetrics(settingsOpen: false)
        XCTAssertTrue(
            appState.systemMonitor.enabledMetrics.contains(.cpu),
            "前置条件：CPU 处于监听中"
        )

        // 指标页 → CPU → 关掉监听开关（两个勾选框只会变灰，勾选照旧留着）
        Defaults[.metricMonitorItems] = [.memory]

        appState.updateEnabledMetrics(settingsOpen: false)
        XCTAssertFalse(
            appState.systemMonitor.enabledMetrics.contains(.cpu),
            "关掉监听必须停止采样，不能因为菜单栏/浮窗还勾着 CPU 就继续采集"
        )
        XCTAssertEqual(
            Defaults[.floatingWindowMetricItems],
            [.cpu, .memory],
            "勾选要保留，等开关重新打开"
        )
    }

    /// 悬浮窗关着时，它的勾选列表也不应把指标拉回采样。
    func testFloatingSelectionDoesNotResurrectSamplingWhenWindowDisabled() {
        Defaults[.metricMonitorItems] = [.memory]
        Defaults[.floatingWindowMetricItems] = [.cpu, .memory]
        Defaults[.floatingWindowEnabled] = false

        let appState = makeAppState()
        appState.updateEnabledMetrics(settingsOpen: false)
        XCTAssertFalse(appState.systemMonitor.enabledMetrics.contains(.cpu))
        XCTAssertTrue(appState.systemMonitor.enabledMetrics.contains(.memory))
    }

    // MARK: - 三个控件各写各的键

    /// 监听开关：只写监听集合，菜单栏与浮窗的勾选、悬浮窗总开关一概不动。
    func testMonitoringSwitchOnlyTouchesMonitoredSet() {
        let before = rowSettings(
            monitored: [.cpu, .memory],
            displayed: [.cpu],
            floatingItems: [.cpu, .memory],
            floatingWindowEnabled: true
        )

        let after = MetricRowPolicy.apply(.setMonitoring(false), to: .cpu, settings: before)
        XCTAssertEqual(after.monitored, [.memory])
        XCTAssertEqual(after.displayed, before.displayed, "关掉监听不清理菜单栏勾选")
        XCTAssertEqual(after.floatingItems, before.floatingItems, "关掉监听不清理浮窗勾选")
        XCTAssertEqual(
            after.floatingWindowEnabled,
            before.floatingWindowEnabled,
            "关掉监听不替用户动悬浮窗总开关"
        )

        XCTAssertEqual(
            MetricRowPolicy.apply(.setMonitoring(true), to: .cpu, settings: after),
            before,
            "重新打开开关后完全回到原状态"
        )
    }

    /// 菜单栏勾选框：只写菜单栏列表。
    func testMenuBarCheckboxOnlyTouchesDisplayedSet() {
        let before = rowSettings(
            monitored: [.cpu, .memory],
            displayed: [],
            floatingItems: [.memory],
            floatingWindowEnabled: true
        )

        let on = MetricRowPolicy.apply(.setMenuBar(true), to: .cpu, settings: before)
        XCTAssertEqual(on.displayed, [.cpu])
        XCTAssertEqual(on.monitored, before.monitored)
        XCTAssertEqual(on.floatingItems, before.floatingItems)
        XCTAssertEqual(on.floatingWindowEnabled, before.floatingWindowEnabled)

        XCTAssertEqual(
            MetricRowPolicy.apply(.setMenuBar(false), to: .cpu, settings: on).displayed,
            []
        )
    }

    /// 浮窗勾选框：勾上要顺带打开悬浮窗（否则勾了没反应）；取消最后一项要关掉总开关。
    func testFloatingCheckboxTurnsWindowOnAndOff() {
        let before = rowSettings(monitored: [.cpu, .memory, .gpu], floatingItems: [.cpu])

        let on = MetricRowPolicy.apply(.setFloating(true), to: .memory, settings: before)
        XCTAssertEqual(on.floatingItems, [.cpu, .memory])
        XCTAssertTrue(on.floatingWindowEnabled, "勾上「浮窗」要一起打开悬浮窗")
        XCTAssertEqual(on.monitored, before.monitored)
        XCTAssertEqual(on.displayed, before.displayed)

        let off = MetricRowPolicy.apply(.setFloating(false), to: .cpu, settings: on)
        XCTAssertEqual(off.floatingItems, [.memory], "取消一项不影响其他项")
        XCTAssertTrue(off.floatingWindowEnabled, "还剩一项时总开关不动")

        let last = MetricRowPolicy.apply(.setFloating(false), to: .memory, settings: off)
        XCTAssertTrue(last.floatingItems.isEmpty)
        XCTAssertFalse(last.floatingWindowEnabled, "取消最后一项要关掉总开关，别留下空面板")
    }

    /// 勾选列表为空时会回退到默认指标，所以「是不是最后一项」必须按实际展示集合算，
    /// 不能拿原始列表算 —— 空列表减去一项仍是空，会把总开关误关。
    func testUncheckingCountsAgainstResolvedItemsNotRawList() {
        // 默认悬浮窗指标 = [.cpu, .memory, .networkDown]
        let before = rowSettings(
            monitored: [.cpu, .memory],
            floatingItems: [],
            floatingWindowEnabled: true
        )

        let after = MetricRowPolicy.apply(.setFloating(false), to: .memory, settings: before)
        XCTAssertEqual(after.floatingItems, [.cpu], "默认集合里剩下的项要保留下来")
        XCTAssertTrue(after.floatingWindowEnabled, "还有可展示项，总开关不该被关掉")
    }

    // MARK: - 展示目标解析（勾选 ∩ 监听）

    func testMenuBarShowsOnlyMonitoredCheckedMetrics() {
        XCTAssertEqual(
            MetricDisplaySelection.resolvedItems(
                stored: [.cpu, .memory],
                monitored: [.cpu],
                fallbackWhenEmpty: false
            ),
            [.cpu],
            "监听关掉的指标不能在菜单栏继续显示陈旧值"
        )
        XCTAssertTrue(
            MetricDisplaySelection.resolvedItems(
                stored: [],
                monitored: [.cpu],
                fallbackWhenEmpty: false
            ).isEmpty,
            "菜单栏空列表就是「不显示指标」，不回退到默认集合"
        )
    }

    func testFloatingDisplayKeepsOnlyMonitoredMetrics() {
        XCTAssertEqual(
            FloatingMetricsSelection.displayedItems(
                stored: [.cpu, .memory, .disk],
                monitored: [.cpu, .disk]
            ),
            [.cpu, .disk]
        )
    }

    func testEmptyStoredListFallsBackToDefaultsWithinMonitored() {
        // 默认悬浮窗指标 = [.cpu, .memory, .networkDown]
        XCTAssertEqual(
            FloatingMetricsSelection.displayedItems(stored: [], monitored: [.cpu, .gpu]),
            [.cpu]
        )
    }

    // MARK: - 悬浮窗面板可见性

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

    /// 勾选里的指标全被关掉监听 → 面板暂时隐藏（而不是把总开关关掉）。
    func testPanelHiddenWhenEverySelectedMetricIsUnmonitored() {
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

    // MARK: - 勾选框的显示状态

    /// 勾选框表达的是「归属」，不掺总开关：总开关关着，勾选照样看得见。
    func testFloatingCheckboxKeepsSelectionWhenWindowDisabled() {
        XCTAssertTrue(
            FloatingMetricsSelection.toggleState(
                for: .cpu,
                stored: [.cpu],
                monitored: [.cpu, .memory],
                windowEnabled: false
            ),
            "关掉悬浮窗总开关不该把勾选显示成未勾选"
        )
    }

    /// 未监听的项虽然被展示集合过滤掉了，勾选框仍要显示**被保留的勾选**；
    /// 否则用户看到「没勾」，与「勾选会被保留、重新打开开关后自动恢复」自相矛盾。
    func testUnmonitoredCheckboxShowsKeptSelection() {
        XCTAssertTrue(
            FloatingMetricsSelection.toggleState(
                for: .cpu,
                stored: [.cpu],
                monitored: [.memory],
                windowEnabled: true
            ),
            "未监听的项要显示被保留的勾选"
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

    // MARK: - 勾选显示与写入必须是同一条规则

    /// 「取消全部勾选 → 再勾回一个」只能勾上这一个。
    ///
    /// 空列表在**勾选显示**侧（`toggleState`）按总开关决定算不算默认集合；写入侧若换了
    /// 口径（例如恒按默认集合算），两边就会分叉——用户看到的是一格勾选，落库的却是一片。
    func testUncheckingEverythingThenCheckingOneLeavesOnlyThatOne() {
        var settings = rowSettings(
            monitored: Set(MetricDisplayItem.allCases),
            floatingItems: Defaults.Keys.defaultFloatingWindowMetricItems,
            floatingWindowEnabled: true
        )
        for item in Defaults.Keys.defaultFloatingWindowMetricItems {
            settings = MetricRowPolicy.apply(.setFloating(false), to: item, settings: settings)
        }
        XCTAssertTrue(settings.floatingItems.isEmpty, "前置条件：全部取消后列表为空")
        XCTAssertFalse(settings.floatingWindowEnabled, "取消最后一项会把总开关关掉")

        settings = MetricRowPolicy.apply(.setFloating(true), to: .cpu, settings: settings)
        XCTAssertEqual(settings.floatingItems, [.cpu], "只勾回一项，不该把默认集合一起带回来")
        XCTAssertTrue(settings.floatingWindowEnabled)
    }

    /// 更强的形式：勾一项只许改变这一项的**勾选显示**，其他行的勾选框一格都不许动。
    func testTogglingFloatingLeavesOtherCheckboxesUntouched() {
        let scenarios: [(stored: Set<MetricDisplayItem>, enabled: Bool)] = [
            ([], false),                    // 取消全部之后
            ([], true),                     // 总开关开着但列表为空（此时算默认集合）
            ([.cpu, .memory], false),
            ([.cpu], true),
        ]
        for scenario in scenarios {
            for item in MetricDisplayItem.allCases {
                let before = rowSettings(
                    monitored: Set(MetricDisplayItem.allCases),
                    floatingItems: scenario.stored,
                    floatingWindowEnabled: scenario.enabled
                )
                let after = MetricRowPolicy.apply(.setFloating(true), to: item, settings: before)
                for other in MetricDisplayItem.allCases where other != item {
                    XCTAssertEqual(
                        checkboxState(of: other, in: after),
                        checkboxState(of: other, in: before),
                        "勾「\(item.rawValue)」不该改变「\(other.rawValue)」的勾选显示"
                            + "（stored=\(scenario.stored.sorted { $0.rawValue < $1.rawValue }),"
                            + " enabled=\(scenario.enabled)）"
                    )
                }
                XCTAssertTrue(
                    checkboxState(of: item, in: after),
                    "被勾的那一项必须显示为已勾选"
                )
            }
        }
    }

    private func checkboxState(of item: MetricDisplayItem, in settings: MetricRowSettings) -> Bool {
        FloatingMetricsSelection.toggleState(
            for: item,
            stored: settings.floatingItems,
            monitored: settings.monitored,
            windowEnabled: settings.floatingWindowEnabled
        )
    }

    /// 「关掉监听 → 面板暂时隐藏 → 重新打开 → 自动恢复」，全程悬浮窗设置不动。
    func testPanelHidesThenComesBackWithoutTouchingFloatingSettings() {
        var settings = rowSettings(
            monitored: [.cpu, .memory],
            floatingItems: [.cpu],
            floatingWindowEnabled: true
        )
        XCTAssertTrue(panelShouldShow(settings), "前置条件：CPU 在监听且勾了浮窗")

        settings = MetricRowPolicy.apply(.setMonitoring(false), to: .cpu, settings: settings)
        XCTAssertFalse(
            panelShouldShow(settings),
            "没有可展示的指标时暂时隐藏面板（而不是关掉总开关）"
        )
        XCTAssertTrue(settings.floatingWindowEnabled, "不许替用户关总开关")

        settings = MetricRowPolicy.apply(.setMonitoring(true), to: .cpu, settings: settings)
        XCTAssertTrue(panelShouldShow(settings), "重新打开开关后面板自动回来")
        XCTAssertEqual(settings.floatingItems, [.cpu], "恢复后展示的仍是用户原先勾选的那一项")
    }

    // MARK: - 悬浮窗视图接线

    /// 悬浮窗尺寸按「实际展示的指标」计算，未监听的项不再占位。
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
            "未监听的指标不应占用悬浮窗宽度"
        )
    }

    /// 悬浮窗视图本身也要按「监听中」过滤——验证 SwiftUI 侧的接线，
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

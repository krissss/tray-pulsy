import AppKit
import Defaults
import Foundation
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - App Constants
// ═══════════════════════════════════════════════════════════════

enum AppConstants {
    /// User-visible app name — read from bundle, single source of truth.
    static let appName: String = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "TrayPulsy"
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 类型安全设置 (Defaults)
// ═══════════════════════════════════════════════════════════════
//
// 使用 sindresorhus/Defaults 替代手写 UserDefaults 封装。
// 所有配置项在此定义，全局通过 Defaults[.key] 访问。

extension Defaults.Keys {
    static let defaultFloatingWindowMetricItems: Set<MetricDisplayItem> = [.cpu, .memory, .networkDown]

    // 皮肤
    static let skin = Key<String>("traypulsy_skin", default: SkinManager.defaultSkinID)

    // 帧率上限
    static let fpsLimit = Key<FPSLimit>("traypulsy_fpsLimit", default: .fps40)

    // 反转动画速度映射：越忙越慢
    static let reverseAnimationSpeed = Key<Bool>("traypulsy_reverseAnimationSpeed", default: false)

    // 皮肤动画播放倍率
    static let skinAnimationSpeed = Key<SkinAnimationSpeed>("traypulsy_skinAnimationSpeed", default: .normal)

    // 速度来源
    static let speedSource = Key<SpeedSource>("traypulsy_speedSource", default: .cpu)

    // 开机启动
    static let launchAtStartup = Key<Bool>("traypulsy_launchAtStartup", default: false)

    // 主题
    static let theme = Key<ThemeMode>("traypulsy_theme", default: .system)

    // 后台监控哪些指标（影响历史记录与尖峰诊断）
    static let metricMonitorItems = Key<Set<MetricDisplayItem>>(
        "traypulsy_metricMonitorItems",
        default: Set(MetricDisplayItem.allCases)
    )

    // 菜单栏显示哪些指标（空 = 关闭）
    static let metricDisplayItems = Key<Set<MetricDisplayItem>>("traypulsy_metricDisplayItems", default: [])

    // 悬浮窗
    static let floatingWindowEnabled = Key<Bool>("traypulsy_floatingWindowEnabled", default: false)
    static let statusBarIconEnabled = Key<Bool>("traypulsy_statusBarIconEnabled", default: true)
    static let floatingWindowAlwaysOnTop = Key<Bool>("traypulsy_floatingWindowAlwaysOnTop", default: true)
    static let floatingWindowShowsSkin = Key<Bool>("traypulsy_floatingWindowShowsSkin", default: true)
    static let floatingWindowMetricsLayout = Key<FloatingWindowMetricsLayout>(
        "traypulsy_floatingWindowMetricsLayout",
        default: .horizontal
    )
    static let floatingWindowBackgroundColor = Key<FloatingWindowColor>(
        "traypulsy_floatingWindowBackgroundColor",
        default: .defaultBackground
    )
    static let floatingWindowBackgroundOpacity = Key<Double>(
        "traypulsy_floatingWindowBackgroundOpacity",
        default: 0.72
    )
    static let floatingWindowTextColor = Key<FloatingWindowColor>(
        "traypulsy_floatingWindowTextColor",
        default: .defaultText
    )
    static let floatingWindowMetricItems = Key<Set<MetricDisplayItem>>(
        "traypulsy_floatingWindowMetricItems",
        default: defaultFloatingWindowMetricItems
    )
    static let floatingWindowPlacement = Key<FloatingWindowPlacement>(
        "traypulsy_floatingWindowPlacement",
        default: .unset
    )

    // 菜单栏（状态栏）文字颜色；默认跟随系统（见 MenuBarTextColorPolicy）。
    //
    // 键名从 `traypulsy_statusBarTextColor` 换成 `traypulsy_menuBarTextColor` 是有意的：
    // 旧键里可能存着「固定的纯白」——那正是当时的默认值，继续沿用会把所有人（包括从未
    // 主动改过颜色的用户）钉死在白字上，浅色壁纸下看不清。换键等于让旧值自然失效。
    static let statusBarTextColor = Key<FloatingWindowColor>(
        "traypulsy_menuBarTextColor",
        default: .followsSystem
    )

    // 采样间隔
    static let sampleInterval = Key<SampleInterval>("traypulsy_sampleInterval", default: .oneSec)

    // 历史时长
    static let historyDuration = Key<HistoryDuration>("traypulsy_historyDuration", default: .min30)

    // 尖峰诊断保留条数
    static let spikeEventLimit = Key<SpikeEventLimit>("traypulsy_spikeEventLimit", default: .events12)

    // 外部皮肤目录
    static let externalSkinPath = Key<String>("traypulsy_externalSkinPath", default: "")

    // 在线皮肤 Manifest URL override；空值表示使用默认在线皮肤库。
    static let onlineSkinManifestURL = Key<String>(
        "traypulsy_onlineSkinManifestURL",
        default: ""
    )

    // 语言
    static let language = Key<AppLanguage>("traypulsy_language", default: .system)

    // 颜色阈值
    static let thresholds = Key<ThresholdConfig>("traypulsy_thresholds", default: .defaults)

    // 尖峰诊断跳升阈值
    static let spikeDeltas = Key<SpikeDeltaConfig>("traypulsy_spikeDeltas", default: .defaults)

    // Pulsy 波形配置
    static let pulsyColorTheme            = Key<PulsyColorTheme>("traypulsy_pulsyColorTheme", default: .fire)
    static let pulsyWaveformStyle         = Key<PulsyWaveformStyle>("traypulsy_pulsyWaveformStyle", default: .ecg)
    static let pulsyLineWidth             = Key<Double>("traypulsy_pulsyLineWidth", default: 1.5)
    static let pulsyGlowIntensity         = Key<Double>("traypulsy_pulsyGlowIntensity", default: 1.0)
    static let pulsyAmplitudeSensitivity  = Key<Double>("traypulsy_pulsyAmplitudeSensitivity", default: 1.0)
}

enum WindowVisibilityPolicy {
    static func normalizedStatusBarIconEnabled(
        floatingWindowEnabled: Bool,
        requested: Bool
    ) -> Bool {
        floatingWindowEnabled ? requested : true
    }
}

/// 菜单栏文字颜色的两种模式。
enum MenuBarTextColorMode: String, CaseIterable, Identifiable {
    case followsSystem
    case custom

    var id: Self { self }

    var label: String {
        switch self {
        case .followsSystem: return L10n.menuBarTextColorModeSystem
        case .custom:        return L10n.menuBarTextColorModeCustom
        }
    }
}

/// 菜单栏文字颜色的读写策略。
///
/// **默认跟随系统**：菜单栏图标本身会随壁纸明暗自动换成黑/白，文字必须能用同一条规则
/// ——用动态色 `NSColor.labelColor`，交给 AppKit 在绘制时按当前菜单栏外观解析。
/// 固定颜色（哪怕是很保险的白色）都会在另一半壁纸上失效，所以它只能作为用户主动选择的
/// 兜底，不能当默认值。
enum MenuBarTextColorPolicy {
    /// 存值 → 模式。哨兵即「跟随系统」。
    static func mode(for stored: FloatingWindowColor) -> MenuBarTextColorMode {
        stored.isFollowsSystem ? .followsSystem : .custom
    }

    /// 从「跟随系统」切到「自定义」时的起点：深色。
    /// 用户主动切过来通常正是因为浅色菜单栏下白字看不清。
    static let customSeed: FloatingWindowColor = .defaultText

    /// 模式 → 存值。切到自定义时保留用户原先选过的颜色，没有才用起点色。
    static func storedValue(
        for mode: MenuBarTextColorMode,
        current: FloatingWindowColor
    ) -> FloatingWindowColor {
        switch mode {
        case .followsSystem: return .followsSystem
        case .custom:        return current.isFollowsSystem ? customSeed : current
        }
    }

    /// 交给 `StatusBarView` 的颜色；`nil` = 跟随系统（由视图回落到 `labelColor`）。
    static func resolvedColor(for stored: FloatingWindowColor) -> NSColor? {
        guard !stored.isFollowsSystem else { return nil }
        return NSColor(srgbRed: stored.red, green: stored.green, blue: stored.blue, alpha: 1)
    }
}

/// 展示目标（菜单栏 / 悬浮窗）实际展示哪些指标。
///
/// 两个展示目标共用同一条规则：**用户勾选 ∩ 正在监听**。指标页的监听开关关掉时
/// 只把两个勾选框变禁用、**不清理勾选**（用户的选择要保留），所以存下来的列表里可能
/// 留着未监听的项；而采样只由 `metricMonitorItems` 驱动，把未监听的项展示出来只会
/// 显示陈旧值。所有需要知道「某处到底显示哪些指标」的地方都必须走这里
/// （菜单栏渲染、悬浮窗视图、悬浮窗面板尺寸、面板可见性），不要各自复制一份解析逻辑。
enum MetricDisplaySelection {
    /// - Parameters:
    ///   - stored: 该展示目标自己的勾选列表。
    ///   - monitored: 指标页里开关处于打开状态的指标。
    ///   - fallbackWhenEmpty: `stored` 为空时是否回退到默认指标集合。
    ///     只有悬浮窗用 `true`（总开关开着却没有列表项不该出现空 HUD）；
    ///     菜单栏恒为 `false`——空列表就是「菜单栏不显示指标」。
    static func resolvedItems(
        stored: Set<MetricDisplayItem>,
        monitored: Set<MetricDisplayItem>,
        fallbackWhenEmpty: Bool
    ) -> Set<MetricDisplayItem> {
        let selected = (fallbackWhenEmpty && stored.isEmpty)
            ? Defaults.Keys.defaultFloatingWindowMetricItems
            : stored
        return selected.intersection(monitored)
    }
}

/// 悬浮窗对「展示哪些指标」的约定。
enum FloatingMetricsSelection {
    /// 悬浮窗面板上要画的指标；列表为空时回退到默认指标集合。
    ///
    /// 只在面板真的可见时才有意义（总开关关着时 `shouldShowPanel` 就是 `false`），
    /// 所以这里可以放心让空列表等同于默认集合。**写入侧不要用这个**——见 `checkedItems`。
    static func displayedItems(
        stored: Set<MetricDisplayItem>,
        monitored: Set<MetricDisplayItem>
    ) -> Set<MetricDisplayItem> {
        MetricDisplaySelection.resolvedItems(
            stored: stored,
            monitored: monitored,
            fallbackWhenEmpty: true
        )
    }

    /// 指标页「浮窗」勾选框所表达的集合——**勾选框的读写两侧共用这一个口径**。
    ///
    /// 「列表为空」的含义取决于总开关：悬浮窗开着的时候用户看到的是默认指标集合，关着的
    /// 时候就是「一项都没勾」。所以读（`toggleState`）与写（`MetricRowPolicy`）必须传同一个
    /// `windowEnabled`；任一侧改口径，都会出现「取消全部勾选 → 再勾回一个」时一次勾回一整片
    /// 的分叉（用户看到一格，落库一片）。
    static func checkedItems(
        stored: Set<MetricDisplayItem>,
        monitored: Set<MetricDisplayItem>,
        windowEnabled: Bool
    ) -> Set<MetricDisplayItem> {
        MetricDisplaySelection.resolvedItems(
            stored: stored,
            monitored: monitored,
            fallbackWhenEmpty: windowEnabled
        )
    }

    /// 悬浮窗面板是否应当显示。
    ///
    /// 总开关之外还要看「是否真有可展示的指标」：指标页把某项的监听开关关掉时不再
    /// 改动悬浮窗设置，所以总开关可能是开着的、而列表里没有任何可展示项。这时把面板
    /// **暂时隐藏**，而不是把用户的总开关关掉——重新打开该项的开关后面板自动回来，
    /// 位置与勾选都不会丢。
    static func shouldShowPanel(
        windowEnabled: Bool,
        stored: Set<MetricDisplayItem>,
        monitored: Set<MetricDisplayItem>
    ) -> Bool {
        guard windowEnabled else { return false }
        return !displayedItems(stored: stored, monitored: monitored).isEmpty
    }

    /// 指标页「浮窗」勾选框的显示状态。
    ///
    /// 勾选框表达的是**归属**（这个指标属于悬浮窗），所以不掺总开关：总开关关掉时
    /// 勾选照样保留，重新打开后展示的仍是原来那几项。未监听的项显示的是用户勾过什么
    /// （勾选框同时被禁用）。
    static func toggleState(
        for item: MetricDisplayItem,
        stored: Set<MetricDisplayItem>,
        monitored: Set<MetricDisplayItem>,
        windowEnabled: Bool
    ) -> Bool {
        guard monitored.contains(item) else { return stored.contains(item) }
        return checkedItems(
            stored: stored,
            monitored: monitored,
            windowEnabled: windowEnabled
        ).contains(item)
    }
}

/// 指标页一行的三个控件所对应的全部状态。
///
/// 整套进、整套出，测试便能逐字段断言「某个控件没有顺手改动别人的键」。
struct MetricRowSettings: Equatable {
    /// 监听开关 → `metricMonitorItems`，全局唯一的采样来源。
    var monitored: Set<MetricDisplayItem>
    /// 「菜单栏」勾选框 → `metricDisplayItems`。
    var displayed: Set<MetricDisplayItem>
    /// 「浮窗」勾选框 → `floatingWindowMetricItems`。
    var floatingItems: Set<MetricDisplayItem>
    /// 悬浮窗总开关 → `floatingWindowEnabled`。
    var floatingWindowEnabled: Bool
}

/// 指标页一行的三种操作。
enum MetricRowAction: Equatable {
    case setMonitoring(Bool)
    case setMenuBar(Bool)
    case setFloating(Bool)
}

/// 指标页一行的写入规则。
///
/// 三个控件各写各的键、互不越界：监听开关关掉时**不清理**菜单栏与悬浮窗的勾选
/// （两个勾选框只是变禁用），重新打开开关后原选择自动生效。这条约束由
/// `MetricRowSettings` 全套进全套出、测试逐字段比对来守住。
enum MetricRowPolicy {
    static func apply(
        _ action: MetricRowAction,
        to item: MetricDisplayItem,
        settings: MetricRowSettings
    ) -> MetricRowSettings {
        var updated = settings
        switch action {
        case .setMonitoring(let isOn):
            if isOn { updated.monitored.insert(item) } else { updated.monitored.remove(item) }

        case .setMenuBar(let isVisible):
            if isVisible { updated.displayed.insert(item) } else { updated.displayed.remove(item) }

        case .setFloating(let isVisible):
            // 基准集合必须和勾选框的**显示**用同一个口径（`checkedItems`，含总开关）。
            // 曾经这里用的是「空列表即默认集合」的展示口径，于是「取消全部勾选 → 再勾回一个」
            // 会把默认集合一起勾回来：用户看到勾的是一格，落库的是一片。
            var items = FloatingMetricsSelection.checkedItems(
                stored: settings.floatingItems,
                monitored: settings.monitored,
                windowEnabled: settings.floatingWindowEnabled
            )
            if isVisible {
                items.insert(item)
                updated.floatingWindowEnabled = true
            } else {
                items.remove(item)
                // 取消最后一项就把总开关也关掉，免得留下一个空面板。
                if items.isEmpty { updated.floatingWindowEnabled = false }
            }
            updated.floatingItems = items
        }
        return updated
    }
}

struct FloatingWindowPlacement: Codable, Defaults.Serializable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let unset = FloatingWindowPlacement(x: -1, y: -1, width: 0, height: 0)

    var hasSavedFrame: Bool {
        width > 0 && height > 0
    }
}

enum FloatingWindowMetricsLayout: String, CaseIterable, Defaults.Serializable, Identifiable {
    case horizontal
    case vertical

    var id: Self { self }

    var displayName: String {
        switch self {
        case .horizontal: return L10n.floatingWindowLayoutHorizontal
        case .vertical:   return L10n.floatingWindowLayoutVertical
        }
    }
}

struct FloatingWindowColor: Codable, Defaults.Serializable, Sendable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let defaultBackground = FloatingWindowColor(red: 0.88, green: 0.88, blue: 0.88)
    static let defaultText = FloatingWindowColor(red: 0.03, green: 0.03, blue: 0.03)
    /// 「跟随系统」哨兵：不使用固定颜色，交给动态色 `NSColor.labelColor` 在绘制时解析。
    /// 菜单栏图标本身就会随壁纸明暗自动换成黑/白，文字必须能用同一条规则，否则浅色壁纸下
    /// 白字会看不见。负值不会与任何真实颜色冲突（sRGB 分量与 ColorPicker 都非负）。
    static let followsSystem = FloatingWindowColor(red: -1, green: -1, blue: -1)

    /// 是否为「跟随系统」哨兵（而非某个具体颜色）。
    var isFollowsSystem: Bool { red < 0 }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .windowBackgroundColor
        red = Double(nsColor.redComponent)
        green = Double(nsColor.greenComponent)
        blue = Double(nsColor.blueComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - FPS Limit
// ═══════════════════════════════════════════════════════════════

enum FPSLimit: String, CaseIterable, Defaults.Serializable {
    case fps10 = "10fps"
    case fps20 = "20fps"
    case fps30 = "30fps"
    case fps40 = "40fps"

    var displayName: String {
        switch self {
        case .fps10: return L10n.fps10
        case .fps20: return L10n.fps20
        case .fps30: return L10n.fps30
        case .fps40: return L10n.fps40
        }
    }

    /// 倍率：用于 TrayAnimator 调节 timer interval
    var rateMultiplier: Double {
        switch self {
        case .fps10: return 4.0
        case .fps20: return 2.0
        case .fps30: return 1.33
        case .fps40: return 1.0
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Skin Animation Speed
// ═══════════════════════════════════════════════════════════════

enum SkinAnimationSpeed: String, CaseIterable, Defaults.Serializable {
    case half = "0.5x"
    case threeQuarter = "0.75x"
    case normal = "1x"
    case oneAndHalf = "1.5x"
    case double = "2x"

    var displayName: String {
        switch self {
        case .half: return L10n.skinAnimationSpeedHalf
        case .threeQuarter: return L10n.skinAnimationSpeedThreeQuarter
        case .normal: return L10n.skinAnimationSpeedNormal
        case .oneAndHalf: return L10n.skinAnimationSpeedOneAndHalf
        case .double: return L10n.skinAnimationSpeedDouble
        }
    }

    var intervalMultiplier: Double {
        switch self {
        case .half: return 2.0
        case .threeQuarter: return 1.33
        case .normal: return 1.0
        case .oneAndHalf: return 0.67
        case .double: return 0.5
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Speed Source
// ═══════════════════════════════════════════════════════════════

enum SpeedSource: String, CaseIterable, Defaults.Serializable {
    case cpu = "cpu"
    case gpu = "gpu"
    case memory = "memory"
    case disk = "disk"

    var label: String {
        switch self {
        case .cpu:    return L10n.speedCpu
        case .gpu:     return L10n.speedGpu
        case .memory:  return L10n.speedMemory
        case .disk:    return L10n.speedDisk
        }
    }

    var systemImage: String {
        switch self {
        case .cpu:    return "cpu"
        case .gpu:     return "square.on.square"
        case .memory:  return "memorychip"
        case .disk:    return "internaldrive"
        }
    }

    /// The SystemMonitor metric kind that drives animation for this source.
    var requiredMetric: SystemMonitor.MetricKind {
        switch self {
        case .cpu:    return .cpu
        case .gpu:     return .gpu
        case .memory:  return .memory
        case .disk:    return .disk
        }
    }

    /// 动画归一化：不同指标的 idle 基线不同，统一到 0~100
    func normalizeForAnimation(_ rawValue: Double) -> Double {
        switch self {
        case .cpu, .gpu:
            return rawValue  // CPU/GPU idle ≈ 0%，直接用
        case .memory:
            // 内存 idle ≈ 70%（系统常驻 + 文件缓存），减去基线
            return max(0, rawValue - 70.0) / (100.0 - 70.0) * 100.0
        case .disk:
            // 磁盘 idle ≈ 60%
            return max(0, rawValue - 60.0) / (100.0 - 60.0) * 100.0
        }
    }

    static func firstAvailable(in monitoredItems: Set<MetricDisplayItem>) -> SpeedSource? {
        allCases.first { source in
            monitoredItems.contains { item in
                item.requiredMetric == source.requiredMetric
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Theme Mode
// ═══════════════════════════════════════════════════════════════

enum ThemeMode: String, CaseIterable, Defaults.Serializable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return L10n.themeSystem
        case .light:  return L10n.themeLight
        case .dark:   return L10n.themeDark
        }
    }

    var isDarkOverride: Bool? {
        switch self {
        case .system: return nil
        case .light:  return false
        case .dark:   return true
        }
    }

    /// Apply this theme to the whole app UI (settings window, popover, floating panel).
    /// `.system` clears the override so the app follows the macOS appearance again.
    /// - Note: this affects only the app's own chrome — skin sprite frames are never
    ///   recolored, and the menu bar status item is unaffected: `NSApp.appearance` does not
    ///   reach `NSStatusItem.button`, whose window is owned by the system (verified). The
    ///   status item therefore keeps matching the real menu bar, which follows the wallpaper
    ///   rather than this override. Do not "restore" a pin here — see `StatusBarController`.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - App Language
// ═══════════════════════════════════════════════════════════════

enum AppLanguage: String, CaseIterable, Defaults.Serializable {
    case system = "system"
    case en     = "en"
    case zhHans = "zh-Hans"

    var displayName: String {
        switch self {
        case .system: return L10n.generalLanguageSystem
        case .en:     return "English"
        case .zhHans: return "中文"
        }
    }

    /// Reload L10n strings. L10n reads Defaults[.language] directly.
    func apply() {
        L10n.reload()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Sample Interval
// ═══════════════════════════════════════════════════════════════

enum SampleInterval: String, CaseIterable, Defaults.Serializable {
    case halfSec = "0.5s"
    case oneSec = "1s"
    case twoSec = "2s"
    case threeSec = "3s"
    case fiveSec = "5s"
    case tenSec = "10s"

    var seconds: TimeInterval {
        switch self {
        case .halfSec:  return 0.5
        case .oneSec:   return 1.0
        case .twoSec:   return 2.0
        case .threeSec: return 3.0
        case .fiveSec:  return 5.0
        case .tenSec:   return 10.0
        }
    }

    var displayName: String {
        switch self {
        case .halfSec:  return L10n.interval05
        case .oneSec:   return L10n.interval1
        case .twoSec:   return L10n.interval2
        case .threeSec: return L10n.interval3
        case .fiveSec:  return L10n.interval5
        case .tenSec:   return L10n.interval10
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - History Duration (趋势图历史时长)
// ═══════════════════════════════════════════════════════════════

enum HistoryDuration: String, CaseIterable, Defaults.Serializable {
    case min5   = "5min"
    case min10  = "10min"
    case min15  = "15min"
    case min30  = "30min"
    case min60  = "60min"

    var seconds: TimeInterval {
        switch self {
        case .min5:  return 300
        case .min10: return 600
        case .min15: return 900
        case .min30: return 1800
        case .min60: return 3600
        }
    }

    var displayName: String {
        switch self {
        case .min5:  return L10n.historyDuration5
        case .min10: return L10n.historyDuration10
        case .min15: return L10n.historyDuration15
        case .min30: return L10n.historyDuration30
        case .min60: return L10n.historyDuration60
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Spike Event Limit (尖峰诊断保留条数)
// ═══════════════════════════════════════════════════════════════

enum SpikeEventLimit: String, CaseIterable, Defaults.Serializable {
    case events4 = "4"
    case events8 = "8"
    case events12 = "12"
    case events24 = "24"
    case events48 = "48"

    var count: Int {
        switch self {
        case .events4:  return 4
        case .events8:  return 8
        case .events12: return 12
        case .events24: return 24
        case .events48: return 48
        }
    }

    var displayName: String {
        switch self {
        case .events4:  return L10n.spikeEventLimit4
        case .events8:  return L10n.spikeEventLimit8
        case .events12: return L10n.spikeEventLimit12
        case .events24: return L10n.spikeEventLimit24
        case .events48: return L10n.spikeEventLimit48
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Metric Display Items (菜单栏多指标显示)
// ═══════════════════════════════════════════════════════════════

enum MetricDisplayItem: String, CaseIterable, Defaults.Serializable, Identifiable {
    case cpu, gpu, memory, disk, networkDown, networkUp

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .cpu:         "CPU"
        case .gpu:         "GPU"
        case .memory:      "RAM"
        case .disk:        "SSD"
        case .networkDown: "NET↓"
        case .networkUp:   "NET↑"
        }
    }

    var displayName: String {
        switch self {
        case .cpu:         L10n.metricCpu
        case .gpu:         L10n.metricGpu
        case .memory:      L10n.metricMemory
        case .disk:        L10n.metricDisk
        case .networkDown: L10n.metricNetDown
        case .networkUp:   L10n.metricNetUp
        }
    }

    /// Chart row label — shared by both Popover and Overview.
    var chartLabel: String {
        switch self {
        case .cpu:         L10n.metricOverviewCpu
        case .gpu:         L10n.metricOverviewGpu
        case .memory:      L10n.metricOverviewMemory
        case .disk:        L10n.metricOverviewDisk
        case .networkDown: L10n.overviewNetwork
        case .networkUp:   L10n.overviewNetwork
        }
    }

    /// Icon name for the full-row chart view (network gets a combined icon).
    var chartIcon: String {
        switch self {
        case .networkDown, .networkUp: return "antenna.radiowaves.left.and.right"
        case .cpu:    return "cpu"
        case .gpu:    return "square.on.square"
        case .memory: return "memorychip"
        case .disk:   return "internaldrive"
        }
    }

    /// Fixed semantic color for chart/row accent — consistent across Popover and Overview.
    var accentColor: NSColor {
        switch self {
        case .cpu:         .systemBlue
        case .gpu:         .systemPink
        case .memory:      .systemOrange
        case .disk:        .systemGreen
        case .networkDown: .systemPurple
        case .networkUp:   .systemPurple
        }
    }

    /// Display order for all chart rows.
    static let chartOrder: [MetricDisplayItem] = [.cpu, .gpu, .memory, .disk, .networkDown]

    static func monitoredChartItems(from monitoredItems: Set<MetricDisplayItem>) -> [MetricDisplayItem] {
        chartOrder.filter { item in
            switch item {
            case .networkDown:
                return monitoredItems.contains(.networkDown)
                    || (!monitoredItems.contains(.networkDown) && monitoredItems.contains(.networkUp))
            default:
                return monitoredItems.contains(item)
            }
        }
        .map { item in
            if item == .networkDown, !monitoredItems.contains(.networkDown), monitoredItems.contains(.networkUp) {
                return .networkUp
            }
            return item
        }
    }

    static func items(for metrics: Set<SystemMonitor.MetricKind>) -> Set<MetricDisplayItem> {
        var items = Set<MetricDisplayItem>()
        if metrics.contains(.cpu) {
            items.insert(.cpu)
        }
        if metrics.contains(.gpu) {
            items.insert(.gpu)
        }
        if metrics.contains(.memory) {
            items.insert(.memory)
        }
        if metrics.contains(.disk) {
            items.insert(.disk)
        }
        if metrics.contains(.network) {
            items.insert(.networkDown)
            items.insert(.networkUp)
        }
        return items
    }

    /// The history key path for this metric's chart data.
    var historyKeyPath: KeyPath<MetricSnapshot, Double> {
        switch self {
        case .cpu:         return \.cpuUsage
        case .gpu:         return \.gpuUsage
        case .memory:      return \.memoryUsage
        case .disk:        return \.diskUsage
        case .networkDown: return \.netSpeedIn
        case .networkUp:   return \.netSpeedOut
        }
    }

    /// Format a hover tooltip value for this metric.
    func formatChartValue(_ v: Double) -> String {
        switch self {
        case .cpu, .gpu, .memory, .disk:
            return String(format: "%.1f%%", v)
        case .networkDown, .networkUp:
            if v >= 1_000_000 { return String(format: "%.1f MB/s", v / 1_000_000) }
            if v >= 1_000 { return String(format: "%.0f KB/s", v / 1_000) }
            return String(format: "%.0f B/s", v)
        }
    }

    var requiredMetric: SystemMonitor.MetricKind {
        switch self {
        case .cpu:         return .cpu
        case .gpu:         return .gpu
        case .memory:      return .memory
        case .disk:        return .disk
        case .networkDown: return .network
        case .networkUp:   return .network
        }
    }

    func formatValue(from monitor: SystemMonitor) -> String {
        switch self {
        case .cpu:    String(format: "%2.0f%%", monitor.cpuUsage)
        case .gpu:    String(format: "%2.0f%%", monitor.gpuUsage)
        case .memory: String(format: "%2.0f%%", monitor.memoryUsage)
        case .disk:   String(format: "%2.0f%%", monitor.diskUsage)
        case .networkDown: Self.formatSpeed(monitor.netSpeedIn)
        case .networkUp:   Self.formatSpeed(monitor.netSpeedOut)
        }
    }

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        let raw: String
        if bytesPerSec >= 1_000_000 {
            raw = String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            raw = String(format: "%.0fK", bytesPerSec / 1_000)
        } else {
            raw = String(format: "%.0fB", bytesPerSec)
        }
        // Left-pad to 5 chars for stable width (right-aligned)
        let pad = max(0, 5 - raw.count)
        return String(repeating: " ", count: pad) + raw
    }

    /// Raw numeric value from monitor (for color threshold computation).
    func rawValue(from monitor: SystemMonitor) -> Double {
        switch self {
        case .cpu:         return monitor.cpuUsage
        case .gpu:         return monitor.gpuUsage
        case .memory:      return monitor.memoryUsage
        case .disk:        return monitor.diskUsage
        case .networkDown: return monitor.netSpeedIn
        case .networkUp:   return monitor.netSpeedOut
        }
    }

    /// Resolve color based on raw value and threshold config.
    func color(forRawValue value: Double, thresholds: ThresholdConfig) -> NSColor {
        let t: MetricThresholds
        switch self {
        case .cpu:         t = thresholds.cpu
        case .gpu:         t = thresholds.gpu
        case .memory:      t = thresholds.memory
        case .disk:        t = thresholds.disk
        case .networkDown: t = thresholds.networkDown
        case .networkUp:   t = thresholds.networkUp
        }
        if value >= t.critical { return .systemRed }
        if value >= t.warning  { return .systemYellow }
        return .textColor
    }

    /// Threshold override color, or `nil` while the value is within its normal range.
    ///
    /// This is the API both text surfaces (menu bar, floating window) use: `nil` means
    /// "no threshold crossed", so each surface falls back to its own user-selected base
    /// text color instead of the `.textColor` sentinel leaking into the view layer.
    func thresholdColor(forRawValue value: Double, thresholds: ThresholdConfig) -> NSColor? {
        let color = color(forRawValue: value, thresholds: thresholds)
        return color == .textColor ? nil : color
    }

    /// Key path for accessing this metric's thresholds in ThresholdConfig.
    var thresholdKeyPath: WritableKeyPath<ThresholdConfig, MetricThresholds> {
        switch self {
        case .cpu:         \.cpu
        case .gpu:         \.gpu
        case .memory:      \.memory
        case .disk:        \.disk
        case .networkDown: \.networkDown
        case .networkUp:   \.networkUp
        }
    }

    /// Unit label for the settings UI.
    var unitLabel: String {
        switch self {
        case .cpu, .gpu, .memory, .disk: return "%"
        case .networkDown, .networkUp:   return "B/s"
        }
    }

    // MARK: - Shared display helpers (Popover + Overview)

    /// Formatted value string for chart rows. Network shows combined ↓/↑.
    func formattedValue(from monitor: SystemMonitor) -> String {
        formattedValue(from: monitor, monitoredItems: Set(MetricDisplayItem.allCases))
    }

    func formattedValue(from monitor: SystemMonitor, monitoredItems: Set<MetricDisplayItem>) -> String {
        if self == .networkDown, monitoredItems.contains(.networkUp) {
            let down = MetricDisplayItem.networkDown.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
            let up = MetricDisplayItem.networkUp.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
            return "↓\(down)/s  ↑\(up)/s"
        }
        if self == .networkDown {
            let down = MetricDisplayItem.networkDown.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
            return "↓\(down)/s"
        }
        if self == .networkUp {
            let up = MetricDisplayItem.networkUp.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
            return "↑\(up)/s"
        }
        return formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
    }

    func formattedValue(
        from snapshot: MetricSnapshot,
        fallback monitor: SystemMonitor,
        monitoredItems: Set<MetricDisplayItem>
    ) -> String {
        switch self {
        case .cpu:
            guard snapshot.records(MetricDisplayItem.cpu) else {
                return formattedValue(from: monitor, monitoredItems: monitoredItems)
            }
            return String(format: "%.0f%%", snapshot.cpuUsage)
        case .gpu:
            guard snapshot.records(MetricDisplayItem.gpu) else {
                return formattedValue(from: monitor, monitoredItems: monitoredItems)
            }
            return String(format: "%.0f%%", snapshot.gpuUsage)
        case .memory:
            guard snapshot.records(MetricDisplayItem.memory) else {
                return formattedValue(from: monitor, monitoredItems: monitoredItems)
            }
            return String(format: "%.0f%%", snapshot.memoryUsage)
        case .disk:
            guard snapshot.records(MetricDisplayItem.disk) else {
                return formattedValue(from: monitor, monitoredItems: monitoredItems)
            }
            return String(format: "%.0f%%", snapshot.diskUsage)
        case .networkDown, .networkUp:
            return networkValueText(from: snapshot, fallback: monitor, monitoredItems: monitoredItems)
        }
    }

    private func networkValueText(
        from snapshot: MetricSnapshot,
        fallback monitor: SystemMonitor,
        monitoredItems: Set<MetricDisplayItem>
    ) -> String {
        func speedText(for item: MetricDisplayItem) -> String {
            let value: Double
            switch item {
            case .networkDown:
                value = snapshot.records(MetricDisplayItem.networkDown) ? snapshot.netSpeedIn : monitor.netSpeedIn
            case .networkUp:
                value = snapshot.records(MetricDisplayItem.networkUp) ? snapshot.netSpeedOut : monitor.netSpeedOut
            default:
                value = 0
            }
            return MetricDisplayItem.formatSpeed(value).trimmingCharacters(in: .whitespaces)
        }

        if self == .networkDown, monitoredItems.contains(.networkUp) {
            return "↓\(speedText(for: .networkDown))/s  ↑\(speedText(for: .networkUp))/s"
        }
        if self == .networkDown {
            return "↓\(speedText(for: .networkDown))/s"
        }
        return "↑\(speedText(for: .networkUp))/s"
    }

    /// Memory used / total detail string (only meaningful for .memory).
    static func memoryDetailText(from monitor: SystemMonitor) -> String {
        let f = ByteCountFormatter(); f.countStyle = .memory
        let used = f.string(fromByteCount: Int64(monitor.memoryUsedGB * 1_073_741_824))
        let total = f.string(fromByteCount: Int64(monitor.memoryTotalGB * 1_073_741_824))
        return "\(used) / \(total)"
    }

    /// Threshold zones for chart annotation lines.
    func thresholdZones(from config: ThresholdConfig) -> [(value: Double, color: Color)] {
        let t: MetricThresholds
        switch self {
        case .cpu:         t = config.cpu
        case .gpu:         t = config.gpu
        case .memory:      t = config.memory
        case .disk:        t = config.disk
        case .networkDown: t = config.networkDown
        case .networkUp:   t = config.networkUp
        }
        return [(value: t.critical, color: .red), (value: t.warning, color: .yellow)]
    }

    /// Whether this metric participates in spike diagnostics.
    var supportsSpikeDiagnostics: Bool {
        switch self {
        case .cpu, .memory, .networkDown, .networkUp:
            return true
        case .gpu, .disk:
            return false
        }
    }

    /// Key path for accessing this metric's spike jump threshold.
    var spikeDeltaKeyPath: WritableKeyPath<SpikeDeltaConfig, Double>? {
        switch self {
        case .cpu:         return \.cpu
        case .memory:      return \.memory
        case .networkDown: return \.networkDown
        case .networkUp:   return \.networkUp
        case .gpu, .disk:  return nil
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Color Thresholds
// ═══════════════════════════════════════════════════════════════

struct MetricThresholds: Codable, Defaults.Serializable, Sendable {
    var warning: Double
    var critical: Double
}

struct ThresholdConfig: Codable, Defaults.Serializable, Sendable {
    var cpu: MetricThresholds
    var gpu: MetricThresholds
    var memory: MetricThresholds
    var disk: MetricThresholds
    var networkDown: MetricThresholds
    var networkUp: MetricThresholds

    static let defaults = ThresholdConfig(
        cpu: .init(warning: 70, critical: 90),
        gpu: .init(warning: 70, critical: 90),
        memory: .init(warning: 80, critical: 95),
        disk: .init(warning: 80, critical: 95),
        networkDown: .init(warning: 1_000_000, critical: 10_000_000),
        networkUp: .init(warning: 500_000, critical: 5_000_000)
    )
}

struct SpikeDeltaConfig: Codable, Defaults.Serializable, Sendable {
    var cpu: Double
    var memory: Double
    var networkDown: Double
    var networkUp: Double

    static let defaults = SpikeDeltaConfig(
        cpu: 25,
        memory: 8,
        networkDown: 500_000,
        networkUp: 250_000
    )
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Pulsy Waveform Config
// ═══════════════════════════════════════════════════════════════

enum PulsyColorTheme: String, CaseIterable, Defaults.Serializable {
    case fire, ocean, matrix, neon, monochrome

    var displayName: String {
        switch self {
        case .fire:       return L10n.pulsyColorFire
        case .ocean:      return L10n.pulsyColorOcean
        case .matrix:     return L10n.pulsyColorMatrix
        case .neon:       return L10n.pulsyColorNeon
        case .monochrome: return L10n.pulsyColorMonochrome
        }
    }

    /// Three gradient stops: start, mid, end.
    var gradientStops: [NSColor] {
        switch self {
        case .fire:       return [NSColor(red: 1, green: 1, blue: 1, alpha: 1),
                                  NSColor(red: 1, green: 1, blue: 0, alpha: 1),
                                  NSColor(red: 1, green: 0.15, blue: 0, alpha: 1)]
        case .ocean:      return [NSColor(red: 0, green: 1, blue: 1, alpha: 1),
                                  NSColor(red: 0, green: 0.4, blue: 1, alpha: 1),
                                  NSColor(red: 0.6, green: 0, blue: 1, alpha: 1)]
        case .matrix:     return [NSColor(red: 0.2, green: 1, blue: 0.3, alpha: 1),
                                  NSColor(red: 0, green: 0.8, blue: 0.1, alpha: 1),
                                  NSColor(red: 0, green: 0.5, blue: 0.05, alpha: 1)]
        case .neon:       return [NSColor(red: 1, green: 0, blue: 0.6, alpha: 1),
                                  NSColor(red: 0.8, green: 0, blue: 1, alpha: 1),
                                  NSColor(red: 0.2, green: 0.4, blue: 1, alpha: 1)]
        case .monochrome: return [NSColor(red: 1, green: 1, blue: 1, alpha: 1),
                                  NSColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1),
                                  NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)]
        }
    }

    /// Representative colour for settings UI preview.
    var iconColor: NSColor { gradientStops[1] }
}

enum PulsyWaveformStyle: String, CaseIterable, Defaults.Serializable {
    case ecg, sine, sawtooth, square, spike

    var displayName: String {
        switch self {
        case .ecg:      return L10n.pulsyWaveEcg
        case .sine:     return L10n.pulsyWaveSine
        case .sawtooth: return L10n.pulsyWaveSawtooth
        case .square:   return L10n.pulsyWaveSquare
        case .spike:    return L10n.pulsyWaveSpike
        }
    }

    var systemImage: String {
        switch self {
        case .ecg:      return "heart.fill"
        case .sine:     return "waveform.path"
        case .sawtooth: return "chart.line.flattrend.xyaxis"
        case .square:   return "rectangle.split.3x1"
        case .spike:    return "bolt.fill"
        }
    }
}

struct PulsyConfig: Sendable, Equatable {
    let colorTheme: PulsyColorTheme
    let waveformStyle: PulsyWaveformStyle
    let lineWidth: CGFloat
    let glowIntensity: CGFloat
    let amplitudeSensitivity: CGFloat

    static let defaults = PulsyConfig(
        colorTheme: .fire, waveformStyle: .ecg,
        lineWidth: 1.5, glowIntensity: 1.0, amplitudeSensitivity: 1.0
    )
}

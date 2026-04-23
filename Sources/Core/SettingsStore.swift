import AppKit
import Defaults
import Foundation

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
    // 皮肤
    static let skin = Key<String>("traypulsy_skin", default: "cat")

    // 帧率上限
    static let fpsLimit = Key<FPSLimit>("traypulsy_fpsLimit", default: .fps40)

    // 速度来源
    static let speedSource = Key<SpeedSource>("traypulsy_speedSource", default: .cpu)

    // 开机启动
    static let launchAtStartup = Key<Bool>("traypulsy_launchAtStartup", default: false)

    // 主题
    static let theme = Key<ThemeMode>("traypulsy_theme", default: .system)

    // 菜单栏显示哪些指标（空 = 关闭）
    static let metricDisplayItems = Key<Set<MetricDisplayItem>>("traypulsy_metricDisplayItems", default: [])

    // 采样间隔
    static let sampleInterval = Key<SampleInterval>("traypulsy_sampleInterval", default: .oneSec)

    // 外部皮肤目录
    static let externalSkinPath = Key<String>("traypulsy_externalSkinPath", default: "")

    // 语言
    static let language = Key<AppLanguage>("traypulsy_language", default: .system)

    // 颜色阈值
    static let thresholds = Key<ThresholdConfig>("traypulsy_thresholds", default: .defaults)
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

    var emoji: String {
        switch self {
        case .system: return "🌓"
        case .light:  return "☀️"
        case .dark:   return "🌙"
        }
    }

    var isDarkOverride: Bool? {
        switch self {
        case .system: return nil
        case .light:  return false
        case .dark:   return true
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
// MARK: - Metric Display Items (菜单栏多指标显示)
// ═══════════════════════════════════════════════════════════════

enum MetricDisplayItem: String, CaseIterable, Defaults.Serializable, Identifiable {
    case cpu, gpu, memory, disk, networkDown, networkUp

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .cpu:         "cpu"
        case .gpu:         "gpu"
        case .memory:      "mem"
        case .disk:        "disk"
        case .networkDown: "net↓"
        case .networkUp:   "net↑"
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

    var overviewName: String {
        switch self {
        case .cpu:         L10n.metricOverviewCpu
        case .gpu:         L10n.metricOverviewGpu
        case .memory:      L10n.metricOverviewMemory
        case .disk:        L10n.metricOverviewDisk
        case .networkDown: L10n.metricOverviewDown
        case .networkUp:   L10n.metricOverviewUp
        }
    }

    var icon: String {
        switch self {
        case .cpu:         "cpu"
        case .gpu:         "square.on.square"
        case .memory:      "memorychip"
        case .disk:        "internaldrive"
        case .networkDown: "arrow.down"
        case .networkUp:   "arrow.up"
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

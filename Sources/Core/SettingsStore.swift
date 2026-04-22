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
        case .fps10: return "10 FPS"
        case .fps20: return "20 FPS"
        case .fps30: return "30 FPS"
        case .fps40: return "40 FPS"
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
        case .cpu:    return "CPU"
        case .gpu:     return "GPU"
        case .memory:  return "内存"
        case .disk:    return "磁盘"
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
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
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
        case .halfSec:  return "0.5 秒"
        case .oneSec:   return "1 秒"
        case .twoSec:   return "2 秒"
        case .threeSec: return "3 秒"
        case .fiveSec:  return "5 秒"
        case .tenSec:   return "10 秒"
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
        case .cpu:         "CPU 使用率"
        case .gpu:         "GPU 使用率"
        case .memory:      "内存"
        case .disk:        "磁盘"
        case .networkDown: "下行网速"
        case .networkUp:   "上行网速"
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
}

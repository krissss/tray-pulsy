import Defaults
import Foundation

// ═══════════════════════════════════════════════════════════════
// MARK: - 类型安全设置 (Defaults)
// ═══════════════════════════════════════════════════════════════
//
// 使用 sindresorhus/Defaults 替代手写 UserDefaults 封装。
// 所有配置项在此定义，全局通过 Defaults[.key] 访问。

extension Defaults.Keys {
    // 皮肤
    static let skin = Key<String>("runcatx_skin", default: "cat")

    // 帧率上限
    static let fpsLimit = Key<FPSLimit>("runcatx_fpsLimit", default: .fps40)

    // 速度来源
    static let speedSource = Key<SpeedSource>("runcatx_speedSource", default: .cpu)

    // 开机启动
    static let launchAtStartup = Key<Bool>("runcatx_launchAtStartup", default: false)

    // 主题
    static let theme = Key<ThemeMode>("runcatx_theme", default: .system)

    // 菜单栏显示数值文字
    static let showMetricText = Key<Bool>("runcatx_showMetricText", default: false)

    // 采样间隔
    static let sampleInterval = Key<SampleInterval>("runcatx_sampleInterval", default: .oneSec)

    // 外部皮肤目录
    static let externalSkinPath = Key<String>("runcatx_externalSkinPath", default: "")
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

    /// 倍率：用于 CatAnimator 调节 timer interval
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

    var emoji: String {
        switch self {
        case .cpu:    return "cpu"
        case .gpu:     return "square.on.square"
        case .memory:  return "memorychip"
        case .disk:    return "internaldrive"
        }
    }

    /// 动画归一化：不同指标的 idle 基线不同，统一到 0~100
    func normalizeForAnimation(_ rawValue: Double) -> Double {
        switch self {
        case .cpu, .gpu:
            return rawValue  // CPU/GPU idle ≈ 0%，直接用
        case .memory:
            // 内存 idle ≈ 45%（系统常驻），减去基线
            return max(0, rawValue - 45.0) / (100.0 - 45.0) * 100.0
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

    var seconds: TimeInterval {
        switch self {
        case .halfSec:  return 0.5
        case .oneSec:   return 1.0
        case .twoSec:   return 2.0
        case .threeSec: return 3.0
        }
    }

    var displayName: String {
        switch self {
        case .halfSec:  return "0.5 秒"
        case .oneSec:   return "1 秒"
        case .twoSec:   return "2 秒"
        case .threeSec: return "3 秒"
        }
    }
}

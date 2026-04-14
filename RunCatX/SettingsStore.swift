import Foundation

/// Persistent settings via UserDefaults.
/// All configurable options are saved here and restored on launch.
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()
    private nonisolated(unsafe) let defaults = UserDefaults.standard
    private let prefix = "com.runcatx."

    // MARK: - Keys

    private enum Key: String {
        case skin, fpsLimit, speedSource, launchAtStartup, theme, showInDock, showCPUText
    }

    // MARK: - Skin

    var skin: String {
        get { defaults.string(forKey: prefix + Key.skin.rawValue) ?? "cat" }
        set { defaults.set(newValue, forKey: prefix + Key.skin.rawValue) }
    }

    // MARK: - FPS Limit

    var fpsLimit: FPSLimit {
        get {
            let raw = defaults.string(forKey: prefix + Key.fpsLimit.rawValue) ?? "fps40"
            return FPSLimit(rawValue: raw) ?? .fps40
        }
        set { defaults.set(newValue.rawValue, forKey: prefix + Key.fpsLimit.rawValue) }
    }

    // MARK: - Speed Source

    var speedSource: SpeedSource {
        get {
            let raw = defaults.string(forKey: prefix + Key.speedSource.rawValue) ?? "cpu"
            return SpeedSource(rawValue: raw) ?? .cpu
        }
        set { defaults.set(newValue.rawValue, forKey: prefix + Key.speedSource.rawValue) }
    }

    // MARK: - Launch At Startup

    var launchAtStartup: Bool {
        get { defaults.bool(forKey: prefix + Key.launchAtStartup.rawValue) }
        set { defaults.set(newValue, forKey: prefix + Key.launchAtStartup.rawValue) }
    }

    // MARK: - Theme

    var theme: ThemeMode {
        get {
            let raw = defaults.string(forKey: prefix + Key.theme.rawValue) ?? "system"
            return ThemeMode(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: prefix + Key.theme.rawValue) }
    }

    // MARK: - Show Metric Text in Menu Bar
    // Backing key remains "showCPUText" for backward compatibility with existing prefs.

    var showMetricText: Bool {
        get { defaults.bool(forKey: prefix + Key.showCPUText.rawValue) }
        set { defaults.set(newValue, forKey: prefix + Key.showCPUText.rawValue) }
    }

    /// Legacy alias — same storage.
    var showCPUText: Bool { showMetricText }

    // MARK: - Restore

    func restore() {
        // Validate all settings have defaults — no-op if already set
        _ = skin; _ = fpsLimit; _ = speedSource; _ = launchAtStartup; _ = theme; _ = showCPUText
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Value Types
// ═══════════════════════════════════════════════════════════════

enum FPSLimit: String, CaseIterable, Sendable {
    case fps40 = "40fps", fps30 = "30fps", fps20 = "20fps", fps10 = "10fps"

    /// Rate multiplier relative to 40fps baseline (1.0)
    var rateMultiplier: Double {
        switch self {
        case .fps40: return 1.0
        case .fps30: return 0.75
        case .fps20: return 0.5
        case .fps10: return 0.25
        }
    }

    var label: String { rawValue }
}

enum SpeedSource: String, CaseIterable, Sendable {
    case cpu = "cpu", memory = "memory", disk = "disk"

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Animation Normalization
    // ═════════════════════════════════════════════════════════

    /// Raw usage (0–100) → animation-friendly value (0–100).
    ///
    /// The animator's interval formula was designed for CPU where idle ≈ 0%.
    /// Memory on macOS sits at 50–70% during normal use, and disks are often
    /// 60–80% full — so we remap them so typical usage feels "idle/slow".
    func normalizeForAnimation(_ rawValue: Double) -> Double {
        switch self {
        case .cpu:
            // Idle really is ~0%
            return max(0, min(100, rawValue))
        case .memory:
            // macOS memory baseline ≈ 45% (wired + compressed + active)
            let baseline: Double = 45.0
            let normalized = (rawValue - baseline) / (100.0 - baseline) * 100.0
            return max(0, min(100, normalized))
        case .disk:
            // Disks commonly 60% full; pressure starts at 85%+
            let baseline: Double = 60.0
            let normalized = (rawValue - baseline) / (100.0 - baseline) * 100.0
            return max(0, min(100, normalized))
        }
    }
}

enum ThemeMode: String, CaseIterable, Sendable {
    case system = "system", light = "light", dark = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var emoji: String {
        switch self {
        case .system: return "🖥"
        case .light: return "☀️"
        case .dark: return "🌙"
        }
    }

    /// Whether dark appearance should be forced
    var isDarkOverride: Bool? {
        switch self {
        case .system: return nil
        case .light: return false
        case .dark: return true
        }
    }
}

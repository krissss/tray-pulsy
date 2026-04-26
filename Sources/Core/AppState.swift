import AppKit
import Defaults
import Observation

// ═══════════════════════════════════════════════════════════════
// MARK: - AppState (Centralized State Container)
// ═══════════════════════════════════════════════════════════════

/// Single owner of all managers and settings coordination.
/// SwiftUI views access via `@Environment(AppState.self)`.
@MainActor
@Observable
final class AppState {
    let systemMonitor: SystemMonitor
    let skinManager: SkinManager
    let updateManager: AppUpdateManager

    // Callbacks — registered by StatusBarController
    var onSkinChanged: (([NSImage]) -> Void)?
    var onFPSLimitChanged: ((FPSLimit) -> Void)?
    var onMetricsConfigChanged: (() -> Void)?
    var onPulsyConfigChanged: (() -> Void)?
    var onSampleIntervalChanged: ((SampleInterval) -> Void)?
    var onExternalSkinPathChanged: (() -> Void)?

    private var defaultsObservers: [Defaults.Observation] = []

    init(
        systemMonitor: SystemMonitor,
        skinManager: SkinManager,
        updateManager: AppUpdateManager
    ) {
        self.systemMonitor = systemMonitor
        self.skinManager = skinManager
        self.updateManager = updateManager
    }

    func activate() {
        systemMonitor.start()
        setupDefaultsObservers()
    }

    func deactivate() {
        systemMonitor.stop()
        defaultsObservers.forEach { $0.invalidate() }
        defaultsObservers.removeAll()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Defaults Observers
    // ═════════════════════════════════════════════════════════

    private func setupDefaultsObservers() {
        defaultsObservers = [
            Defaults.observe(.skin) { [weak self] change in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let s = self.skinManager.skin(for: change.newValue)
                    self.skinManager.setSkin(s)
                    self.onSkinChanged?(self.skinManager.frames(for: s))
                }
            },
            Defaults.observe(.speedSource) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onMetricsConfigChanged?()
                }
            },
            Defaults.observe(.fpsLimit) { [weak self] change in
                MainActor.assumeIsolated {
                    self?.onFPSLimitChanged?(change.newValue)
                }
            },
            Defaults.observe(.sampleInterval) { [weak self] change in
                MainActor.assumeIsolated {
                    self?.onSampleIntervalChanged?(change.newValue)
                    self?.systemMonitor.reconfigure(sampleInterval: change.newValue.seconds)
                }
            },
            Defaults.observe(.metricDisplayItems) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onMetricsConfigChanged?()
                }
            },
            Defaults.observe(.externalSkinPath) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.skinManager.reload()
                    self.onExternalSkinPathChanged?()
                }
            },
            Defaults.observe(.thresholds) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onMetricsConfigChanged?()
                }
            },
            Defaults.observe(.pulsyColorTheme) { [weak self] _ in
                MainActor.assumeIsolated { self?.handlePulsyConfigChange() }
            },
            Defaults.observe(.pulsyWaveformStyle) { [weak self] _ in
                MainActor.assumeIsolated { self?.handlePulsyConfigChange() }
            },
            Defaults.observe(.pulsyLineWidth) { [weak self] _ in
                MainActor.assumeIsolated { self?.handlePulsyConfigChange() }
            },
            Defaults.observe(.pulsyGlowIntensity) { [weak self] _ in
                MainActor.assumeIsolated { self?.handlePulsyConfigChange() }
            },
            Defaults.observe(.pulsyAmplitudeSensitivity) { [weak self] _ in
                MainActor.assumeIsolated { self?.handlePulsyConfigChange() }
            },
        ]
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ═════════════════════════════════════════════════════════

    /// Only read the metrics we actually need.
    func updateEnabledMetrics(settingsOpen: Bool) {
        if settingsOpen {
            systemMonitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
        } else {
            var needed = Set([Defaults[.speedSource].requiredMetric])
            if !Defaults[.metricDisplayItems].isEmpty {
                needed.formUnion(Defaults[.metricDisplayItems].map(\.requiredMetric))
            }
            systemMonitor.enabledMetrics = needed
        }
    }

    /// Current normalized value for the active speed source.
    func currentNormalizedValue() -> Double {
        let source = Defaults[.speedSource]
        let rawValue = systemMonitor.valueForSource(source)
        return source.normalizeForAnimation(rawValue)
    }

    /// Regenerate Pulsy frames with current config + value.
    func regeneratePulsyFrames() -> [NSImage] {
        let config = SkinManager.currentPulsyConfig()
        return PulsySkinRenderer.generateFrames(value: currentNormalizedValue(), config: config)
    }

    private func handlePulsyConfigChange() {
        guard skinManager.currentSkin.id == "pulsy" else { return }
        onPulsyConfigChanged?()
    }
}

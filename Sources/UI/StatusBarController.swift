import Defaults
import SwiftUI

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   CLICK → Open native Settings window (Cmd+,)
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SystemMonitor.shared
    private var animator: TrayAnimator!
    private let skinManager = SkinManager.shared
    private var updateTimer: Timer?
    private var defaultsObservers: [Defaults.Observation] = []
    private var settingsWindow: NSWindow?
    private let statusBarView = StatusBarView()
    private var lastDisplayedMetricText: String = ""

    /// Only read the metrics we actually need.
    private func updateEnabledMetrics() {
        let settingsOpen = settingsWindow?.isVisible == true
        if settingsOpen {
            monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
        } else {
            var needed = Set([Defaults[.speedSource].requiredMetric])
            if !Defaults[.metricDisplayItems].isEmpty {
                needed.formUnion(Defaults[.metricDisplayItems].map(\.requiredMetric))
            }
            monitor.enabledMetrics = needed
        }
    }

    func start() {
        // 1. Create animator with initial frames
        let initialFrames = skinManager.frames()
        animator = TrayAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback — update StatusBarView's frame image
        animator.onFrameUpdate = { [weak self] image in
            self?.statusBarView.setFrameImage(image)
        }

        // 3. Apply saved skin
        let savedSkin = skinManager.skin(for: Defaults[.skin])
        skinManager.setSkin(savedSkin)
        animator.changeSkin(to: skinManager.frames(for: savedSkin))

        // 5. Apply FPS limit
        animator.setFPSLimit(Defaults[.fpsLimit])

        // 6. Configure button: any click → open settings
        setupButton()

        // 7. Start everything
        monitor.start()
        animator.start()
        startUpdateTimer()
        updateEnabledMetrics()

        // 8. Listen for settings changes via Defaults
        setupDefaultsObservers()

        // 9. Listen for language changes to update window title & accessibility
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: L10n.languageDidChangeNotification,
            object: nil
        )
    }

    func stop() {
        monitor.stop()
        animator.stop()
        updateTimer?.invalidate(); updateTimer = nil
        settingsWindow?.close()
        settingsWindow = nil
        defaultsObservers.forEach { $0.invalidate() }
        defaultsObservers.removeAll()
        NotificationCenter.default.removeObserver(self, name: L10n.languageDidChangeNotification, object: nil)
    }

    nonisolated func pause() {
        Task { @MainActor in animator.pause() }
    }

    nonisolated func resume() {
        Task { @MainActor in animator.resume() }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Button
    // ═════════════════════════════════════════════════════════

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = NSImage()  // clear native image — StatusBarView handles all drawing
        button.addSubview(statusBarView)
        syncStatusItemLength()
    }

    @objc private func statusItemClicked() { openSettings() }

    /// Keep NSStatusItem.length in sync with StatusBarView's required width.
    private func syncStatusItemLength() {
        statusItem.length = statusBarView.requiredWidth
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Window
    // ═════════════════════════════════════════════════════════

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)

        let targetWindow: NSWindow
        if let existing = settingsWindow, existing.isVisible {
            targetWindow = existing
        } else {
            let view = NSHostingView(rootView: SettingsView())
            if let existing = settingsWindow {
                existing.contentView = view
                targetWindow = existing
            } else {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = view
                window.isReleasedWhenClosed = false
                window.center()
                window.delegate = self
                window.title = "\(AppConstants.appName) \(L10n.windowTitle)"
                window.titlebarAppearsTransparent = true
                settingsWindow = window
                targetWindow = window
            }
            updateEnabledMetrics()
        }

        targetWindow.makeKeyAndOrderFront(nil)
        // Enable all metrics now that the window is visible
        monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateEnabledMetrics()
        // Defer SwiftUI teardown to next run loop to avoid layout recursion
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.contentView = nil
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Update Timer
    // ═════════════════════════════════════════════════════════

    /// Single timer drives: animator speed + metric text + accessibility.
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                // Drive animator with current metric value
                let source = Defaults[.speedSource]
                let rawValue = self.monitor.valueForSource(source)
                let normalizedValue = source.normalizeForAnimation(rawValue)
                self.animator.updateValue(normalizedValue)

                // Dynamic Pulsy skin: regenerate frames with current value for colour/amplitude
                if self.skinManager.currentSkin.id == "pulsy" {
                    let config = SkinManager.currentPulsyConfig()
                    self.animator.updateFrames(PulsySkinRenderer.generateFrames(value: normalizedValue, config: config))
                }

                // Update metric text & accessibility (only when values change)
                let selected = Defaults[.metricDisplayItems]
                if selected.isEmpty {
                    if !self.lastDisplayedMetricText.isEmpty {
                        self.lastDisplayedMetricText = ""
                        self.statusBarView.clear()
                        self.syncStatusItemLength()
                        self.updateAccessibilityLabel()
                    }
                } else {
                    let items = MetricDisplayItem.allCases.filter { selected.contains($0) }
                    let values = items.map { $0.formatValue(from: self.monitor) }
                    let thresholds = Defaults[.thresholds]
                    let colors = items.map { $0.color(forRawValue: $0.rawValue(from: self.monitor), thresholds: thresholds) }
                    let joined = values.joined(separator: " ")
                    if joined != self.lastDisplayedMetricText {
                        self.lastDisplayedMetricText = joined
                        self.statusBarView.setItems(items, sampleValues: values, colors: colors)
                        self.statusBarView.updateValues(values, colors: colors)
                        self.syncStatusItemLength()
                        self.updateAccessibilityLabel()
                    } else {
                        self.statusBarView.updateValues(values, colors: colors)
                    }
                }
            }
        }
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
                    self.animator.changeSkin(to: self.skinManager.frames(for: s))
                }
            },
            Defaults.observe(.speedSource) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateEnabledMetrics()
                }
            },
            Defaults.observe(.fpsLimit) { [weak self] change in
                MainActor.assumeIsolated {
                    self?.animator.setFPSLimit(change.newValue)
                }
            },
            Defaults.observe(.sampleInterval) { [weak self] change in
                MainActor.assumeIsolated {
                    self?.monitor.reconfigure(sampleInterval: change.newValue.seconds)
                }
            },
            Defaults.observe(.metricDisplayItems) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateEnabledMetrics()
                    self.refreshMetricDisplay()
                }
            },
            Defaults.observe(.externalSkinPath) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.skinManager.reload()
                    self.animator.changeSkin(to: self.skinManager.frames())
                }
            },
            Defaults.observe(.thresholds) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshMetricDisplay()
                }
            },
            Defaults.observe(.pulsyColorTheme) { [weak self] _ in
                MainActor.assumeIsolated { self?.regeneratePulsyFrames() }
            },
            Defaults.observe(.pulsyWaveformStyle) { [weak self] _ in
                MainActor.assumeIsolated { self?.regeneratePulsyFrames() }
            },
            Defaults.observe(.pulsyLineWidth) { [weak self] _ in
                MainActor.assumeIsolated { self?.regeneratePulsyFrames() }
            },
            Defaults.observe(.pulsyGlowIntensity) { [weak self] _ in
                MainActor.assumeIsolated { self?.regeneratePulsyFrames() }
            },
            Defaults.observe(.pulsyAmplitudeSensitivity) { [weak self] _ in
                MainActor.assumeIsolated { self?.regeneratePulsyFrames() }
            },
        ]
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ═════════════════════════════════════════════════════════

    /// Force-refresh metric display (called by observers when settings change).
    private func refreshMetricDisplay() {
        let selected = Defaults[.metricDisplayItems]
        guard !selected.isEmpty else {
            lastDisplayedMetricText = ""
            statusBarView.clear()
            syncStatusItemLength()
            updateAccessibilityLabel()
            return
        }
        let items = MetricDisplayItem.allCases.filter { selected.contains($0) }
        let values = items.map { $0.formatValue(from: monitor) }
        let thresholds = Defaults[.thresholds]
        let colors = items.map { $0.color(forRawValue: $0.rawValue(from: monitor), thresholds: thresholds) }
        lastDisplayedMetricText = values.joined(separator: " ")
        statusBarView.setItems(items, sampleValues: values, colors: colors)
        statusBarView.updateValues(values, colors: colors)
        syncStatusItemLength()
        updateAccessibilityLabel()
    }

    /// Immediately regenerate Pulsy frames with current config + value.
    private func regeneratePulsyFrames() {
        guard skinManager.currentSkin.id == "pulsy" else { return }
        let config = SkinManager.currentPulsyConfig()
        let source = Defaults[.speedSource]
        let rawValue = monitor.valueForSource(source)
        let normalizedValue = source.normalizeForAnimation(rawValue)
        animator.updateFrames(PulsySkinRenderer.generateFrames(value: normalizedValue, config: config))
    }

    private func updateAccessibilityLabel() {
        let text: String
        if !Defaults[.metricDisplayItems].isEmpty, !lastDisplayedMetricText.isEmpty {
            text = "\(AppConstants.appName) \(lastDisplayedMetricText)\(L10n.accClickToOpen)"
        } else {
            text = "\(AppConstants.appName)\(L10n.accClickToOpen)"
        }
        statusItem.button?.setAccessibilityLabel(text)
    }

    @objc private func handleLanguageChange() {
        if let window = settingsWindow {
            window.title = "\(AppConstants.appName) \(L10n.windowTitle)"
        }
        updateAccessibilityLabel()
    }
}

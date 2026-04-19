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
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var updateTimer: Timer?
    private var defaultsObservers: [Defaults.Observation] = []
    private var settingsWindow: NSWindow?
    private var lastDisplayedMetricValue: Double = -1

    /// Only read the metrics we actually need.
    private func updateEnabledMetrics() {
        let settingsOpen = settingsWindow?.isVisible == true
        if settingsOpen {
            monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
        } else {
            monitor.enabledMetrics = [Defaults[.speedSource].requiredMetric]
        }
    }

    func start() {
        // 1. Create animator with initial frames
        let initialFrames = skinManager.frames()
        animator = CatAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback — ONLY update image per frame (cheap)
        animator.onFrameUpdate = { [weak self] image, _ in
            self?.statusItem.button?.image = image
        }

        // 3. Apply theme FIRST (invalidates skin cache before loading frames)
        applyTheme(Defaults[.theme])

        // 4. Apply saved skin (after theme so frames use correct appearance)
        if let savedSkin = skinManager.allSkins.first(where: { $0.id == Defaults[.skin] }) {
            skinManager.setSkin(savedSkin)
            animator.changeSkin(to: skinManager.frames(for: savedSkin))
        }

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
    }

    func stop() {
        monitor.stop()
        animator.stop()
        updateTimer?.invalidate(); updateTimer = nil
        settingsWindow?.close()
        settingsWindow = nil
        defaultsObservers.forEach { $0.invalidate() }
        defaultsObservers.removeAll()
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
        button.imageHugsTitle = true
        button.imagePosition = .imageLeft
    }

    @objc private func statusItemClicked() { openSettings() }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Window
    // ═════════════════════════════════════════════════════════

    private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let view = NSHostingView(rootView: SettingsView())
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
        window.title = "RunCatX 设置"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        updateEnabledMetrics()
    }

    func windowWillClose(_ notification: Notification) {
        updateEnabledMetrics()
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
                self.animator.updateValue(source == .cpu || source == .gpu
                    ? rawValue
                    : source.normalizeForAnimation(rawValue))

                // Update metric text & accessibility (only when integer value changes)
                let newValue = self.currentMetricValue()
                let clampedNew = min(newValue, 99.0)
                if Int(clampedNew) != Int(self.lastDisplayedMetricValue) {
                    self.lastDisplayedMetricValue = clampedNew
                    self.applyMetricTextMode()
                    self.updateAccessibilityLabel()
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme
    // ═════════════════════════════════════════════════════════

    private func applyTheme(_ mode: ThemeMode) {
        skinManager.setTheme(mode)

        guard let dark = mode.isDarkOverride else {
            NSApp.appearance = nil; return
        }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Metric Text
    // ═════════════════════════════════════════════════════════

    private func applyMetricTextMode() {
        if Defaults[.showMetricText] {
            let clamped = min(currentMetricValue(), 99.0)
            let value = "\(clamped.formatted(.number.precision(.fractionLength(0))))%"
            let fontSize = 12.0
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .kern: -0.3
            ]
            statusItem.button?.attributedTitle = NSAttributedString(string: value, attributes: attributes)
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.length = NSStatusItem.squareLength
        }
    }

    private func currentMetricValue() -> Double {
        monitor.valueForSource(Defaults[.speedSource])
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Defaults Observers
    // ═════════════════════════════════════════════════════════

    private func setupDefaultsObservers() {
        defaultsObservers = [
            Defaults.observe(.skin) { [weak self] change in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let s = self.skinManager.allSkins.first(where: { $0.id == change.newValue }) {
                        self.skinManager.setSkin(s)
                        self.animator.changeSkin(to: self.skinManager.frames(for: s))
                    }
                }
            },
            Defaults.observe(.speedSource) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateEnabledMetrics()
                    self.applyMetricTextMode()
                    self.updateAccessibilityLabel()
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
            Defaults.observe(.theme) { [weak self] change in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.applyTheme(change.newValue)
                    self.animator.changeSkin(to: self.skinManager.frames())
                }
            },
            Defaults.observe(.showMetricText) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyMetricTextMode()
                }
            },
            Defaults.observe(.externalSkinPath) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.skinManager.reload()
                    self.animator.changeSkin(to: self.skinManager.frames())
                }
            },
        ]
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Accessibility
    // ═════════════════════════════════════════════════════════

    private func updateAccessibilityLabel() {
        let source = Defaults[.speedSource]
        let value = monitor.valueForSource(source)
        let displayValue = min(value, 99.0)
        let text = Defaults[.showMetricText]
            ? "RunCatX \(source.label) \(displayValue.formatted(.number.precision(.fractionLength(0))))%，点击打开设置"
            : "RunCatX，点击打开设置"
        statusItem.button?.setAccessibilityLabel(text)
    }
}

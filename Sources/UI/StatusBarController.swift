import Combine
import SwiftUI
import Defaults

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   CLICK → Open Settings window (TabView sidebarAdaptable UI)
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var monitor: SystemMonitor!
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var syncTimer: Timer?

    private var settingsObservers: [NSObjectProtocol] = []
    private var lastDisplayedMetricValue: Double = -1

    func start() {
        // 1. Create monitor & animator
        monitor = SystemMonitor(sampleInterval: Defaults[.sampleInterval].seconds)
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

        // 6. Wire speed source (Combine — 1Hz)
        bindSpeedSource(Defaults[.speedSource])

        // 7. Configure button: any click → open settings
        setupButton()

        // 8. Configure which metrics to read (minimize per-tick work)
        updateEnabledMetrics()

        // 9. Start everything LAST
        monitor.start()
        animator.start()
        startSyncTimer()

        // 10. Listen for settings changes
        setupSettingsObservers()
    }

    func stop() {
        monitor.stop()
        animator.stop()
        syncTimer?.invalidate(); syncTimer = nil
        settingsWindow?.close()
        settingsWindow = nil
        settingsObservers.forEach { NotificationCenter.default.removeObserver($0) }
        settingsObservers.removeAll()
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

    func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)

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
        activateApp()
    }

    func windowWillClose(_ notification: Notification) { updateEnabledMetrics() }

    // ═════════════════════════════════════════════════════════
    // MARK: - App Activation
    // ═════════════════════════════════════════════════════════

    private func activateApp() {
        NSApp.activate()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Enabled Metrics
    // ═════════════════════════════════════════════════════════

    private func updateEnabledMetrics() {
        guard settingsWindow == nil || !(settingsWindow?.isVisible ?? false) else {
            monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
            return
        }

        var metrics: Set<SystemMonitor.MetricKind> = []
        switch Defaults[.speedSource] {
        case .cpu:    metrics.insert(.cpu)
        case .gpu:    metrics.insert(.gpu)
        case .memory: metrics.insert(.memory)
        case .disk:   metrics.insert(.disk)
        }
        monitor.enabledMetrics = metrics
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Speed Source Binding
    // ═════════════════════════════════════════════════════════

    private func bindSpeedSource(_ source: SpeedSource) {
        switch source {
        case .cpu:
            monitor.$cpuUsage
                .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] value in
                    self?.animator.updateValue(value)
                }.store(in: &cancellables)

        case .gpu:
            monitor.$gpuUsage
                .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] value in
                    self?.animator.updateValue(value)
                }.store(in: &cancellables)

        case .memory:
            monitor.$memoryUsage
                .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] value in
                    self?.animator.updateValue(SpeedSource.memory.normalizeForAnimation(value))
                }.store(in: &cancellables)

        case .disk:
            monitor.$diskUsage
                .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] value in
                    self?.animator.updateValue(SpeedSource.disk.normalizeForAnimation(value))
                }.store(in: &cancellables)
        }
    }

    private func rebindSpeedSource(_ newSource: SpeedSource) {
        cancellables.removeAll()
        bindSpeedSource(newSource)
        updateEnabledMetrics()
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
        let source = Defaults[.speedSource]
        switch source {
        case .cpu:    return ObservableMonitor.shared.cpuUsage
        case .gpu:    return ObservableMonitor.shared.gpuUsage
        case .memory: return ObservableMonitor.shared.memoryUsage
        case .disk:   return ObservableMonitor.shared.diskUsage
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Sync Timer
    // ═════════════════════════════════════════════════════════

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                ObservableMonitor.shared.sync(from: self.monitor)

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
    // MARK: - Settings Change Observers
    // ═════════════════════════════════════════════════════════

    private func setupSettingsObservers() {
        let names: [(Notification.Name, @Sendable (Any?) -> Void)] = [
            (.speedSourceChanged, { obj in
                let src = (obj as? String).flatMap(SpeedSource.init(rawValue:))
                MainActor.assumeIsolated {
                    if let src { self.rebindSpeedSource(src) }
                }
            }),
            (.fpsLimitChanged, { obj in
                let m = obj as? Double
                MainActor.assumeIsolated {
                    if let m { self.animator.setFPSLimit(fromMultiplier: m) }
                }
            }),
            (.sampleIntervalChanged, { obj in
                let s = obj as? TimeInterval
                MainActor.assumeIsolated {
                    if let s { self.monitor.reconfigure(sampleInterval: s) }
                }
            }),
            (.skinChanged, { obj in
                let id = obj as? String
                MainActor.assumeIsolated {
                    if let id, let s = self.skinManager.allSkins.first(where: { $0.id == id }) {
                        self.skinManager.setSkin(s)
                        self.animator.changeSkin(to: self.skinManager.frames(for: s))
                    }
                }
            }),
            (.themeChanged, { obj in
                let t = (obj as? String).flatMap(ThemeMode.init(rawValue:))
                MainActor.assumeIsolated {
                    if let t {
                        self.applyTheme(t)
                        self.animator.changeSkin(to: self.skinManager.frames())
                    }
                }
            }),
            (.metricTextChanged, { _ in
                MainActor.assumeIsolated {
                    self.applyMetricTextMode()
                }
            }),
            (.externalSkinPathChanged, { _ in
                MainActor.assumeIsolated {
                    self.skinManager.reload()
                    self.animator.changeSkin(to: self.skinManager.frames())
                }
            }),
        ]

        for (name, handler) in names {
            let obs = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                handler(note.object)
            }
            settingsObservers.append(obs)
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Accessibility
    // ═════════════════════════════════════════════════════════

    private func updateAccessibilityLabel() {
        let source = Defaults[.speedSource]
        let value = ObservableMonitor.shared.valueForSource(source)
        let displayValue = min(value, 99.0)
        let text = Defaults[.showMetricText]
            ? "RunCatX \(source.label) \(displayValue.formatted(.number.precision(.fractionLength(0))))%，点击打开设置"
            : "RunCatX，点击打开设置"
        statusItem.button?.setAccessibilityLabel(text)
    }
}

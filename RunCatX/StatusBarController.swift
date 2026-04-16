import AppKit
import Combine
import ServiceManagement
import SwiftUI
import Defaults

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   CLICK → Open Settings window (NavigationSplitView sidebar UI)
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var monitor: SystemMonitor!
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var syncTimer: Timer?

    // Notification tokens for settings changes
    private var settingsObservers: [NSObjectProtocol] = []

    func start() {
        // 1. Create monitor & animator
        monitor = SystemMonitor(sampleInterval: Defaults[.sampleInterval].seconds)
        let initialFrames = skinManager.frames()
        animator = CatAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback (image + accessibility + metric text)
        animator.onFrameUpdate = { [weak self] image, fps in
            guard let self = self else { return }
            self.statusItem.button?.image = image
            self.applyMetricTextMode()
            self.updateAccessibilityLabel(fps)
        }

        // 3. Apply saved settings BEFORE starting
        animator.setFPSLimit(Defaults[.fpsLimit])
        if let savedSkin = SkinManager.Skin(rawValue: Defaults[.skin]) {
            skinManager.setSkin(savedSkin)
            animator.changeSkin(to: skinManager.frames(for: savedSkin))
        }

        // 4. Wire speed source (Combine — 1Hz)
        bindSpeedSource(Defaults[.speedSource])

        // 5. Apply theme
        applyTheme(Defaults[.theme])

        // 6. Configure button: any click → open settings
        setupButton()

        // 7. Start everything LAST
        monitor.start()
        animator.start()
        startSyncTimer()

        // 8. Listen for settings changes
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

    func pause() {
        animator.pause()
    }

    func resume() {
        animator.resume()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Button
    // ═════════════════════════════════════════════════════════

    private func setupButton() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        openSettings()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Window
    // ═════════════════════════════════════════════════════════

    func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RunCatX 设置"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    /// Rebind speed source when user changes it from settings.
    private func rebindSpeedSource(_ newSource: SpeedSource) {
        cancellables.removeAll()
        bindSpeedSource(newSource)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme
    // ═════════════════════════════════════════════════════════

    private func applyTheme(_ mode: ThemeMode) {
        guard let dark = mode.isDarkOverride else {
            NSApp.appearance = nil; return
        }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Metric Text (数值文字显示)
    // ═════════════════════════════════════════════════════════

    /// 在图标旁边显示当前指标数值（如 "45%"）
    private func applyMetricTextMode() {
        if Defaults[.showMetricText] {
            statusItem.button?.title = String(format: "%.0f%%", currentMetricValue())
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    /// 获取当前 speedSource 对应的原始值（用于显示）
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
    // MARK: - Sync Timer (feeds ObservableMonitor for Settings UI)
    // ═════════════════════════════════════════════════════════

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            ObservableMonitor.shared.sync(from: self.monitor)
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Change Observers
    // ═════════════════════════════════════════════════════════

    private func setupSettingsObservers() {
        let names: [(Notification.Name, (Any?) -> Void)] = [
            (.speedSourceChanged,     { raw in
                if let raw = raw as? String, let src = SpeedSource(rawValue: raw) {
                    self.rebindSpeedSource(src)
                }
            }),
            (.fpsLimitChanged,       { multiplier in
                if let m = multiplier as? Double {
                    self.animator.setFPSLimit(fromMultiplier: m)
                }
            }),
            (.sampleIntervalChanged, { seconds in
                if let s = seconds as? TimeInterval {
                    self.monitor.reconfigure(sampleInterval: s)
                }
            }),
            (.skinChanged,           { raw in
                if let raw = raw as? String, let s = SkinManager.Skin(rawValue: raw) {
                    self.skinManager.setSkin(s)
                    self.animator.changeSkin(to: self.skinManager.frames(for: s))
                }
            }),
            (.themeChanged,          { raw in
                if let raw = raw as? String, let t = ThemeMode(rawValue: raw) {
                    self.applyTheme(t)
                }
            }),
            (.metricTextChanged,     { _ in
                self.applyMetricTextMode()
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

    private func updateAccessibilityLabel(_ fps: Double) {
        let source = Defaults[.speedSource]
        let value = ObservableMonitor.shared.valueForSource(source)
        let text = Defaults[.showMetricText]
            ? "RunCatX \(source.label) \(String(format: "%.0f%%", value))，点击打开设置"
            : "RunCatX，点击打开设置"
        statusItem.button?.setAccessibilityLabel(text)
    }
}

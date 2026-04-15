import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   CLICK → Open Settings window (all config + system info lives there)
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SystemMonitor(sampleInterval: SettingsStore.shared.sampleInterval.seconds)
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var syncTimer: Timer?

    // Notification tokens for settings window changes
    private var settingsObservers: [NSObjectProtocol] = []

    func start() {
        // 1. Create animator
        let initialFrames = skinManager.frames()
        animator = CatAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback (image + accessibility only)
        animator.onFrameUpdate = { [weak self] image, fps in
            guard let self = self else { return }
            self.statusItem.button?.image = image
            self.updateAccessibilityLabel(fps)
        }

        // 3. Apply saved settings BEFORE starting
        animator.setFPSLimit(SettingsStore.shared.fpsLimit)
        if let savedSkin = SkinManager.Skin(rawValue: SettingsStore.shared.skin) {
            skinManager.setSkin(savedSkin)
            animator.changeSkin(to: skinManager.frames(for: savedSkin))
        }

        // 4. Wire speed source (Combine — 1Hz)
        bindSpeedSource(SettingsStore.shared.speedSource)

        // 5. Apply theme
        applyTheme(SettingsStore.shared.theme)

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

        // Apply metric text mode
        applyMetricTextMode()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        openSettings(sender)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Sync Timer (feeds ObservableMonitor for SwiftUI)
    // ═════════════════════════════════════════════════════════

    /// Periodically mirrors SystemMonitor data → ObservableMonitor
    /// so the Settings window shows live values.
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            ObservableMonitor.shared.sync(from: self.monitor)
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Window
    // ═════════════════════════════════════════════════════════

    @objc func openSettings(_ sender: Any?) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = NSHostingView(rootView: SettingsView())
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "RunCatX"
        win.contentView = view
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Speed Source Binding
    // ═════════════════════════════════════════════════════════

    private func bindSpeedSource(_ source: SpeedSource) {
        cancellables.removeAll(keepingCapacity: true)
        switch source {
        case .cpu:
            monitor.$cpuUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()
                }
                .store(in: &cancellables)
        case .memory:
            monitor.$memoryUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()
                }
                .store(in: &cancellables)
        case .disk:
            monitor.$diskUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()
                }
                .store(in: &cancellables)
        case .gpu:
            monitor.$gpuUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()
                }
                .store(in: &cancellables)
        }
        animator.updateValue(source.normalizeForAnimation(monitor.valueForSource(source)))
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme
    // ═════════════════════════════════════════════════════════

    private func applyTheme(_ mode: ThemeMode) {
        skinManager.setTheme(mode)
        animator.changeSkin(to: skinManager.frames())
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Metric Text Mode
    // ═════════════════════════════════════════════════════════

    /// Applies (or removes) the metric text overlay on the status bar item.
    private func applyMetricTextMode() {
        if SettingsStore.shared.showMetricText {
            statusItem.button?.title = String(format: "%.0f%%", currentMetricValue())
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    private func currentMetricValue() -> Double {
        monitor.valueForSource(SettingsStore.shared.speedSource)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Accessibility
    // ═════════════════════════════════════════════════════════

    private func updateAccessibilityLabel(_ fps: Double) {
        let src = SettingsStore.shared.speedSource
        let val = currentMetricValue()
        statusItem.button?.setAccessibilityLabel(
            String(format: "RunCatX %@ %.0f%% 每秒%.0f帧 点击打开设置",
                   src.label, val, fps)
        )
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Observers
    // ═════════════════════════════════════════════════════════

    private func setupSettingsObservers() {
        let nc = NotificationCenter.default
        settingsObservers.removeAll()

        settingsObservers.append(nc.addObserver(forName: .init("SettingsSpeedSourceChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let src = notification.object as? SpeedSource else { return }
            self?.bindSpeedSource(src)
        })

        settingsObservers.append(nc.addObserver(forName: .init("SettingsFPSLimitChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let fps = notification.object as? FPSLimit else { return }
            self?.animator.setFPSLimit(fps)
        })

        settingsObservers.append(nc.addObserver(forName: .init("SettingsSampleIntervalChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let interval = notification.object as? TimeInterval else { return }
            self?.monitor.reconfigure(sampleInterval: interval)
        })

        settingsObservers.append(nc.addObserver(forName: .init("SettingsThemeChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let mode = notification.object as? ThemeMode else { return }
            self?.applyTheme(mode)
        })

        settingsObservers.append(nc.addObserver(forName: .init("SettingsSkinChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.animator.changeSkin(to: SkinManager.shared.frames())
        })

        settingsObservers.append(nc.addObserver(forName: .init("SettingsShowTextChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.applyMetricTextMode()
        })
    }
}

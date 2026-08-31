import Defaults
import SwiftUI

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   LEFT CLICK  → Toggle metrics popover
///   RIGHT CLICK → Open native Settings window (Cmd+,)
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let appState: AppState
    private var animator: TrayAnimator!
    private var updateTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var floatingPanelController: FloatingMetricsPanelController?
    private let statusBarView = StatusBarView()
    private var lastDisplayedMetricText: String = ""
    private lazy var metricsPopoverPresenter = MetricsPopoverPresenter(
        systemMonitor: appState.systemMonitor,
        updateEnabledMetrics: { [weak self] in
            self?.updateEnabledMetrics()
        },
        openMainWindow: { [weak self] in
            self?.openSettings()
        }
    )

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    // Computed accessors — delegate to AppState
    private var monitor: SystemMonitor { appState.systemMonitor }
    private var skinManager: SkinManager { appState.skinManager }

    func start() {
        // 1. Create animator with initial frames
        let initialFrames = skinManager.frames()
        animator = TrayAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback — update StatusBarView's frame image
        animator.onFrameUpdate = { [weak self] image in
            guard let self else { return }
            self.statusBarView.setFrameImage(image)
            self.floatingPanelController?.setFrameImage(image)
        }

        // 3. Apply saved skin
        let savedSkin = skinManager.skin(for: Defaults[.skin])
        skinManager.setSkin(savedSkin)
        animator.changeSkin(to: skinManager.frames(for: savedSkin))

        // 4. Apply FPS limit
        animator.setFPSLimit(Defaults[.fpsLimit])
        animator.setReverseAnimationSpeed(Defaults[.reverseAnimationSpeed])
        animator.setSkinAnimationSpeed(Defaults[.skinAnimationSpeed])

        // 5. Configure button: left click toggles the popover, right click opens settings
        setupButton()
        syncStatusBarIcon()

        // 6. Start animator and update loop
        animator.start()
        startUpdateLoop()
        updateEnabledMetrics()
        syncFloatingWindow()

        // 7. Register callbacks from AppState
        appState.onSkinChanged = { [weak self] frames in
            self?.animator.changeSkin(to: frames)
        }
        appState.onFPSLimitChanged = { [weak self] limit in
            self?.animator.setFPSLimit(limit)
        }
        appState.onReverseAnimationSpeedChanged = { [weak self] isReversed in
            self?.animator.setReverseAnimationSpeed(isReversed)
        }
        appState.onSkinAnimationSpeedChanged = { [weak self] speed in
            self?.animator.setSkinAnimationSpeed(speed)
        }
        appState.onMetricsConfigChanged = { [weak self] in
            self?.updateEnabledMetrics()
            self?.refreshMetricDisplay()
        }
        appState.onFloatingWindowConfigChanged = { [weak self] in
            self?.syncFloatingWindow()
        }
        appState.onStatusBarIconConfigChanged = { [weak self] in
            self?.syncStatusBarIcon()
        }
        appState.onPulsyConfigChanged = { [weak self] in
            self?.animator.updateFrames(self?.appState.regeneratePulsyFrames() ?? [])
        }
        appState.onSampleIntervalChanged = { [weak self] _ in
            // Stream is re-created by SystemMonitor.reconfigure(), rebuild the task
            self?.startUpdateLoop()
        }
        appState.onExternalSkinPathChanged = { [weak self] in
            guard let self else { return }
            self.animator.changeSkin(to: self.skinManager.frames())
        }
        appState.onSkinLibraryChanged = { [weak self] in
            guard let self else { return }
            self.animator.changeSkin(to: self.skinManager.frames())
        }

        // 8. Listen for language changes to update window title & accessibility
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: L10n.languageDidChangeNotification,
            object: nil
        )
    }

    func stop() {
        appState.deactivate()
        animator.stop()
        updateTask?.cancel()
        updateTask = nil
        metricsPopoverPresenter.close()
        floatingPanelController?.close()
        floatingPanelController = nil
        settingsWindow?.close()
        settingsWindow = nil
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
        // Defer to avoid layoutSubtreeIfNeeded recursion during initial layout
        DispatchQueue.main.async { [weak self] in
            self?.syncStatusItemLength()
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            openSettings()
        } else {
            togglePopover()
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Popover
    // ═════════════════════════════════════════════════════════

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        metricsPopoverPresenter.toggle(anchor: button, preferredEdge: .minY)
    }

    /// Keep NSStatusItem.length in sync with StatusBarView's required width.
    /// Always called async to avoid layout recursion.
    private func syncStatusItemLength() {
        statusItem.length = statusBarView.requiredWidth
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Settings Window
    // ═════════════════════════════════════════════════════════

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)

        let window: NSWindow
        if let existing = settingsWindow, existing.isVisible {
            window = existing
        } else {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.contentView = NSHostingView(rootView: SettingsView().environment(appState))
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            w.title = "\(AppConstants.appName) \(L10n.windowTitle)"
            w.titlebarAppearsTransparent = true
            settingsWindow = w
            window = w
            updateEnabledMetrics()
        }

        window.makeKeyAndOrderFront(nil)
        updateEnabledMetrics()
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    private func openSettingsFromFloatingWindow() {
        openSettings()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateEnabledMetrics()
        // Defer teardown to next run loop to avoid layout recursion
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.contentView = nil
            self?.settingsWindow = nil
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Update Loop (AsyncStream)
    // ═════════════════════════════════════════════════════════

    /// Consume SystemMonitor's AsyncStream to drive animator speed + metric text + accessibility.
    /// Call again to re-subscribe after `reconfigure()` creates a new stream.
    private func startUpdateLoop() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            for await _ in self?.monitor.metricsStream ?? AsyncStream.makeStream().stream {
                guard let self, !Task.isCancelled else { return }

                // Drive animator with current metric value
                let normalizedValue = self.appState.currentNormalizedValue()
                self.animator.updateValue(normalizedValue)

                // Dynamic Pulsy skin: regenerate frames with current value for colour/amplitude
                if self.skinManager.currentSkin.id == "pulsy" {
                    self.animator.updateFrames(self.appState.regeneratePulsyFrames())
                }

                // Update metric text & accessibility (only when values change)
                self.appState.detectMetricSpikeIfNeeded()
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
    // MARK: - Helpers
    // ═════════════════════════════════════════════════════════

    /// Update enabled metrics based on whether settings window is open.
    private func updateEnabledMetrics() {
        let settingsOpen = settingsWindow?.isVisible == true
        appState.updateEnabledMetrics(settingsOpen: settingsOpen)
    }

    private func syncFloatingWindow() {
        if Defaults[.floatingWindowEnabled] {
            let controller = floatingPanelController ?? FloatingMetricsPanelController(
                appState: appState,
                openSettings: { [weak self] in
                    self?.openSettingsFromFloatingWindow()
                },
                popoverPresenter: metricsPopoverPresenter
            )
            floatingPanelController = controller
            controller.show()
            controller.setFrameImage(statusBarView.currentFrame)
            updateEnabledMetrics()
        } else {
            floatingPanelController?.close()
            floatingPanelController = nil
            updateEnabledMetrics()
        }
    }

    private func syncStatusBarIcon() {
        statusItem.isVisible = Defaults[.statusBarIconEnabled]
    }

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

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
        syncStatusBarTextColor()

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
            // 悬浮窗展示的指标是「悬浮窗列表 ∩ 监控中指标」，所以监控集合变化也会
            // 改变展示项数、甚至改变面板是否显示。尺寸不变时是空操作。
            self?.floatingPanelController?.applyWindowSettings()
            self?.syncFloatingWindowVisibility()
        }
        appState.onFloatingWindowConfigChanged = { [weak self] in
            self?.syncFloatingWindow()
        }
        appState.onStatusBarIconConfigChanged = { [weak self] in
            self?.syncStatusBarIcon()
        }
        appState.onStatusBarTextColorChanged = { [weak self] in
            self?.syncStatusBarTextColor()
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
        // 不给按钮设 `appearance`：系统自己会把菜单栏的当前外观交给我们（见下方 MARK 注释）。
        // Defer to avoid layoutSubtreeIfNeeded recursion during initial layout
        DispatchQueue.main.async { [weak self] in
            self?.syncStatusItemLength()
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Menu Bar Appearance
    // ═════════════════════════════════════════════════════════

    // 不要给 `statusItem.button` 设 `appearance`。
    //
    // 曾有过一个 pin：按 `AppleInterfaceStyle`（系统深浅色设置）把按钮钉成
    // vibrantDark/vibrantLight。理由是「按钮会继承 `NSApp.appearance`，app 内的主题覆盖
    // 会让它和真实菜单栏不一致」。两半都不成立，实测（探针程序 + 本机 Light 系统 + 深色壁纸）：
    //
    //   按钮 appearance | 按钮 effectiveAppearance | labelColor
    //   nil（不设）     | VibrantDark（系统给的）   | 白 ✓ 与相邻图标一致
    //   vibrantLight    | VibrantLight              | 黑 ✗ 与相邻图标相反
    //
    // 1. 菜单栏的明暗跟随**壁纸**（本机系统是 Light，但壁纸偏暗 → 系统把整个菜单栏画成暗底、
    //    图标全白）。`AppleInterfaceStyle` 只反映 Light/Dark 设置，据此推导必然推错一半场景——
    //    这正是用户看到的「其他图标是白色，我的文字却是黑的」。
    // 2. `NSApp.appearance = .aqua/.darkAqua` **不会**漏进状态项按钮：按钮的窗口是系统拥有的
    //    `NSStatusBarWindow`，它自带外观，`NSApp.appearance` 只是没有自身外观的对象的兜底。
    //
    // 所以按钮的 effectiveAppearance 就是「系统当前给菜单栏的外观」，把它留给系统即可——
    // `StatusBarView` 里的动态 `labelColor` 会在绘制时按它解析，和相邻图标永远同色。
    // 外观变化（含壁纸切换）由 `StatusBarView.viewDidChangeEffectiveAppearance()` 兜住重绘。

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
                    let overrides = self.thresholdOverrides(for: items)
                    let joined = values.joined(separator: " ")
                    if joined != self.lastDisplayedMetricText {
                        self.lastDisplayedMetricText = joined
                        self.statusBarView.setItems(items, sampleValues: values, valueOverrideColors: overrides)
                        self.statusBarView.updateValues(values, valueOverrideColors: overrides)
                        self.syncStatusItemLength()
                        self.updateAccessibilityLabel()
                    } else {
                        self.statusBarView.updateValues(values, valueOverrideColors: overrides)
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
        if shouldShowFloatingWindow() {
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

    /// 悬浮窗是否显示 = 总开关打开 **且** 确实有可展示的指标。
    ///
    /// 指标 Tab 把某项设为「关闭」不会改动悬浮窗设置，所以会出现「总开关开着、
    /// 但没有任何可展示项」——此时暂时隐藏面板，而不是替用户关掉总开关；
    /// 该项重新启用后面板自动回来。
    private func shouldShowFloatingWindow() -> Bool {
        FloatingMetricsSelection.shouldShowPanel(
            windowEnabled: Defaults[.floatingWindowEnabled],
            stored: Defaults[.floatingWindowMetricItems],
            monitored: Defaults[.metricMonitorItems]
        )
    }

    /// 监控集合变化可能让悬浮窗从「有内容」变成「没内容」或反过来。
    /// 只在显示状态真的翻转时才动面板，避免阈值拖动等高频改动反复重建面板。
    private func syncFloatingWindowVisibility() {
        guard shouldShowFloatingWindow() != (floatingPanelController?.isVisible == true) else { return }
        syncFloatingWindow()
    }

    private func syncStatusBarIcon() {
        statusItem.isVisible = Defaults[.statusBarIconEnabled]
    }

    /// Resolve the effective menu-bar text color and push it to StatusBarView.
    /// `nil` (the default) means "follow the system" — the view then uses the dynamic
    /// `labelColor`, matching however macOS renders the menu bar right now.
    private func syncStatusBarTextColor() {
        statusBarView.setTextColor(
            MenuBarTextColorPolicy.resolvedColor(for: Defaults[.statusBarTextColor])
        )
    }

    /// Per-metric threshold overrides for the menu bar values. `nil` entries stay in the
    /// user-selected text color — the same semantics the floating window uses, so a
    /// normal value never gets recoloured and only a crossed threshold turns it yellow/red.
    private func thresholdOverrides(for items: [MetricDisplayItem]) -> [NSColor?] {
        let thresholds = Defaults[.thresholds]
        return items.map { item in
            item.thresholdColor(forRawValue: item.rawValue(from: monitor), thresholds: thresholds)
        }
    }

    /// 菜单栏实际显示的指标 = 「菜单栏」勾选 ∩ 正在监听。
    ///
    /// 监听开关关掉时不清理勾选（勾选框只是变禁用），列表里会留着未监听的项；
    /// 而采样只由 `metricMonitorItems` 驱动，直接照列表渲染会显示陈旧值。
    private var displayedMetricItems: Set<MetricDisplayItem> {
        MetricDisplaySelection.resolvedItems(
            stored: Defaults[.metricDisplayItems],
            monitored: Defaults[.metricMonitorItems],
            fallbackWhenEmpty: false
        )
    }

    /// Force-refresh metric display (called by observers when settings change).
    private func refreshMetricDisplay() {
        let selected = displayedMetricItems
        guard !selected.isEmpty else {
            lastDisplayedMetricText = ""
            statusBarView.clear()
            syncStatusItemLength()
            updateAccessibilityLabel()
            return
        }
        let items = MetricDisplayItem.allCases.filter { selected.contains($0) }
        let values = items.map { $0.formatValue(from: monitor) }
        let overrides = thresholdOverrides(for: items)
        lastDisplayedMetricText = values.joined(separator: " ")
        statusBarView.setItems(items, sampleValues: values, valueOverrideColors: overrides)
        statusBarView.updateValues(values, valueOverrideColors: overrides)
        syncStatusItemLength()
        updateAccessibilityLabel()
    }

    private func updateAccessibilityLabel() {
        let text: String
        if !displayedMetricItems.isEmpty, !lastDisplayedMetricText.isEmpty {
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

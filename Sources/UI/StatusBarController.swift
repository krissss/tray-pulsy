import Defaults
import SwiftUI

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   LEFT CLICK  → Toggle metrics popover
///   RIGHT CLICK → Open native Settings window (Cmd+,)
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let appState: AppState
    private var animator: TrayAnimator!
    private var updateTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private let statusBarView = StatusBarView()
    private var lastDisplayedMetricText: String = ""

    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.contentSize = NSSize(width: 300, height: 380)
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        return p
    }()

    /// Global mouse-move monitor for auto-hiding popover when mouse leaves.
    private var globalMouseMonitor: Any?
    private var autoHideTask: Task<Void, Never>?

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
            self?.statusBarView.setFrameImage(image)
        }

        // 3. Apply saved skin
        let savedSkin = skinManager.skin(for: Defaults[.skin])
        skinManager.setSkin(savedSkin)
        animator.changeSkin(to: skinManager.frames(for: savedSkin))

        // 4. Apply FPS limit
        animator.setFPSLimit(Defaults[.fpsLimit])

        // 5. Configure button: any click → open settings
        setupButton()

        // 6. Start animator and update loop
        animator.start()
        startUpdateLoop()
        appState.updateEnabledMetrics(settingsOpen: false)

        // 7. Register callbacks from AppState
        appState.onSkinChanged = { [weak self] frames in
            self?.animator.changeSkin(to: frames)
        }
        appState.onFPSLimitChanged = { [weak self] limit in
            self?.animator.setFPSLimit(limit)
        }
        appState.onMetricsConfigChanged = { [weak self] in
            self?.updateEnabledMetrics()
            self?.refreshMetricDisplay()
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
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            // Enable all metrics while popover is visible
            monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
            // Create fresh content each time to avoid holding SwiftUI tree in memory
            popover.contentViewController = NSHostingController(
                rootView: PopoverMetricsView(systemMonitor: monitor)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        startMouseExitMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        stopMouseExitMonitor()
        // Release SwiftUI view tree to free memory
        popover.contentViewController = nil
        updateEnabledMetrics()
    }

    // MARK: - Mouse Exit Auto-Hide

    private func startMouseExitMonitor() {
        stopMouseExitMonitor()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleGlobalMouseMoved()
            }
        }
    }

    private func stopMouseExitMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func handleGlobalMouseMoved() {
        guard popover.isShown else { return }
        guard let window = popover.contentViewController?.view.window else { return }

        let mouseLoc = NSEvent.mouseLocation
        let popoverFrame = window.frame
        // Give a small margin so the user can comfortably interact with the popover edges
        let expandedFrame = popoverFrame.insetBy(dx: -4, dy: -4)

        if !expandedFrame.contains(mouseLoc) {
            autoHideTask?.cancel()
            autoHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                // Re-check before actually closing
                guard let window = self.popover.contentViewController?.view.window else { return }
                let loc = NSEvent.mouseLocation
                if !window.frame.insetBy(dx: -4, dy: -4).contains(loc) {
                    self.popover.performClose(nil)
                }
            }
        } else {
            // Mouse is back inside — cancel any pending close
            autoHideTask?.cancel()
            autoHideTask = nil
        }
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
        monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
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

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

        // 2. Wire direct callback — ONLY update image per frame (cheap)
        animator.onFrameUpdate = { [weak self] image in
            self?.statusItem.button?.image = image
        }

        // 3. Apply theme FIRST (invalidates skin cache before loading frames)
        applyTheme(Defaults[.theme])

        // 4. Apply saved skin (after theme so frames use correct appearance)
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
                window.title = "\(AppConstants.appName) 设置"
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                settingsWindow = window
                targetWindow = window
            }
            updateEnabledMetrics()
        }

        targetWindow.makeKeyAndOrderFront(nil)
        // Enable all metrics now that the window is visible
        monitor.enabledMetrics = Set(SystemMonitor.MetricKind.allCases)
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
                self.animator.updateValue(source.normalizeForAnimation(rawValue))

                // Update metric text & accessibility (only when values change)
                if !Defaults[.metricDisplayItems].isEmpty {
                    let selected = Defaults[.metricDisplayItems]
                    let values = MetricDisplayItem.allCases
                        .filter { selected.contains($0) }
                        .map { $0.formatValue(from: self.monitor) }
                        .joined(separator: " ")
                    if values != self.lastDisplayedMetricText {
                        self.lastDisplayedMetricText = values
                        self.applyMetricTextMode()
                        self.updateAccessibilityLabel()
                    }
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
        let selected = Defaults[.metricDisplayItems]
        if selected.isEmpty {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.length = NSStatusItem.squareLength
            return
        }

        let items = MetricDisplayItem.allCases.filter { selected.contains($0) }

        let labelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .light)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let gap: CGFloat = 6.0

        // Calculate per-column widths (points) and center positions
        var centerPositions: [CGFloat] = []
        var pos: CGFloat = 0
        for item in items {
            let labelW = (item.shortLabel as NSString).size(withAttributes: [.font: labelFont]).width
            let valueW = (item.formatValue(from: monitor) as NSString).size(withAttributes: [.font: valueFont]).width
            let colW = max(labelW, valueW) + gap
            pos += colW
            centerPositions.append(pos - colW / 2)
        }

        // Tab stops at each column's center point — .center alignment centers text on that point
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = centerPositions.map { NSTextTab(textAlignment: .center, location: $0) }
        paragraphStyle.lineHeightMultiple = 0.7

        // Use \t between columns; leading \t centers first column too
        let labelLine = "\t" + items.map(\.shortLabel).joined(separator: "\t")
        let valueLine = "\t" + items.map { $0.formatValue(from: monitor) }.joined(separator: "\t")
        let fullText = labelLine + "\n" + valueLine

        let attrString = NSMutableAttributedString(string: fullText)
        let fullRange = NSRange(location: 0, length: (fullText as NSString).length)
        let newlineRange = (fullText as NSString).range(of: "\n")

        attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        attrString.addAttribute(.baselineOffset, value: -5, range: fullRange)
        attrString.addAttribute(.font, value: labelFont, range: NSRange(location: 0, length: newlineRange.location))
        attrString.addAttribute(.font, value: valueFont, range: NSRange(location: newlineRange.location + 1, length: (fullText as NSString).length - newlineRange.location - 1))

        statusItem.button?.attributedTitle = attrString
        statusItem.length = NSStatusItem.variableLength
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
            Defaults.observe(.metricDisplayItems) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateEnabledMetrics()
                    self.applyMetricTextMode()
                    self.updateAccessibilityLabel()
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
        let text: String
        if !Defaults[.metricDisplayItems].isEmpty, !lastDisplayedMetricText.isEmpty {
            text = "\(AppConstants.appName) \(lastDisplayedMetricText)，点击打开设置"
        } else {
            text = "\(AppConstants.appName)，点击打开设置"
        }
        statusItem.button?.setAccessibilityLabel(text)
    }
}

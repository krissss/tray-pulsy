import AppKit
import Combine

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SystemMonitor(sampleInterval: 1.0)
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var tooltipTimer: Timer?

    func start() {
        animator = CatAnimator(skinManager: skinManager)

        // Restore saved settings
        animator.setFPSLimit(SettingsStore.shared.fpsLimit)
        if let savedSkin = SkinManager.Skin(rawValue: SettingsStore.shared.skin) {
            skinManager.setSkin(savedSkin)
            animator.changeSkin(to: skinManager.frames(for: savedSkin))
        }

        // Wire: speed source value → animator speed
        bindSpeedSource(SettingsStore.shared.speedSource)

        // Wire: animator → button.image (Apple-optimized path)
        animator.$currentFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] img in
                guard let self = self else { return }
                self.statusItem.button?.image = img
                self.updateTooltip()
                self.updateAccessibilityLabel()
            }
            .store(in: &cancellables)

        // Apply theme
        applyTheme(SettingsStore.shared.theme)

        // Configure button
        if let button = statusItem.button {
            button.toolTip = "RunCatX — CPU: --%"
        }

        setupMenu()
        monitor.start()
        animator.start()
        startTooltipUpdates()
    }

    func stop() {
        monitor.stop()
        animator.stop()
        tooltipTimer?.invalidate(); tooltipTimer = nil
    }

    func pause()  { animator.stop() }
    func resume() { animator.start() }

    // ═════════════════════════════════════════════════════════
    // MARK: - Tooltip (hover to show quick stats)
    // ═════════════════════════════════════════════════════════

    private func updateTooltip() {
        statusItem.button?.toolTip = String(
            format: "RunCatX\nCPU: %.1f%% | Mem: %.0f%% | Disk: %.0f%%\n%@",
            monitor.cpuUsage, monitor.memoryUsage, monitor.diskUsage,
            SettingsStore.shared.showCPUText ? "" : "(Right-click for options)"
        )
    }

    private func startTooltipUpdates() {
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateTooltip()
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Accessibility (VoiceOver)
    // ═════════════════════════════════════════════════════════

    private func updateAccessibilityLabel() {
        if let button = statusItem.button {
            button.setAccessibilityLabel(String(
                format: "RunCatX. CPU usage %.1f percent. Animation speed %.0f frames per second.",
                monitor.cpuUsage, animator.framesPerSecond
            ))
            button.setAccessibilityRole(.image)
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Speed Source Binding
    // ═════════════════════════════════════════════════════════

    private func bindSpeedSource(_ source: SpeedSource) {
        cancellables.removeAll(keepingCapacity: true)
        switch source {
        case .cpu:
            monitor.$cpuUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in self?.animator.updateValue(v) }
                .store(in: &cancellables)
        case .memory:
            monitor.$memoryUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in self?.animator.updateValue(v) }
                .store(in: &cancellables)
        }
        // Push current value immediately
        animator.updateValue(monitor.valueForSource(source))
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme (Light/Dark icon recoloring)
    // ═════════════════════════════════════════════════════════

    private func applyTheme(_ mode: ThemeMode) {
        skinManager.setTheme(mode)
        animator?.changeSkin(to: skinManager.frames())
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Menu Setup
    // ═════════════════════════════════════════════════════════

    private func setupMenu() {
        let menu = NSMenu()

        // ── Title with live status ──
        let titleItem = NSMenuItem(title: "🐱 RunCatX", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // ── System Info (live-updating tree) ──
        let sysInfo = NSMenuItem(title: "─", action: nil, keyEquivalent: "")
        sysInfo.isEnabled = false
        menu.addItem(sysInfo)
        menu.addItem(NSMenuItem.separator())

        // ── Show CPU Text toggle ──
        let textToggle = NSMenuItem(
            title: "Show CPU % in Menu Bar",
            action: #selector(toggleShowCPUText(_:)),
            keyEquivalent: ""
        )
        textToggle.state = SettingsStore.shared.showCPUText ? .on : .off
        textToggle.target = self
        menu.addItem(textToggle)
        menu.addItem(NSMenuItem.separator())

        // ── Runner / Skin ──
        let skinMenu = NSMenu()
        for skin in SkinManager.Skin.allCases {
            let item = NSMenuItem(title: skin.label, action: #selector(selectSkin(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = skin.rawValue
            if skin == skinManager.currentSkin { item.state = .on }
            skinMenu.addItem(item)
        }
        let skinItem = NSMenuItem(title: "Skin: \(skinManager.currentSkin.label)", action: nil, keyEquivalent: "")
        skinItem.submenu = skinMenu
        menu.addItem(skinItem)

        // ── Speed Source ──
        let srcMenu = NSMenu()
        for src in SpeedSource.allCases {
            let item = NSMenuItem(title: src.label, action: #selector(selectSpeedSource(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = src.rawValue
            if src == SettingsStore.shared.speedSource { item.state = .on }
            srcMenu.addItem(item)
        }
        let srcItem = NSMenuItem(title: "Speed By: \(SettingsStore.shared.speedSource.label)", action: nil, keyEquivalent: "")
        srcItem.submenu = srcMenu
        menu.addItem(srcItem)

        // ── FPS Limit ──
        let fpsMenu = NSMenu()
        for fps in FPSLimit.allCases {
            let item = NSMenuItem(title: fps.label, action: #selector(selectFPSLimit(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = fps.rawValue
            if fps == SettingsStore.shared.fpsLimit { item.state = .on }
            fpsMenu.addItem(item)
        }
        let fpsItem = NSMenuItem(title: "Max FPS: \(SettingsStore.shared.fpsLimit.label)", action: nil, keyEquivalent: "")
        fpsItem.submenu = fpsMenu
        menu.addItem(fpsItem)

        // ── Theme ──
        let themeMenu = NSMenu()
        for theme in ThemeMode.allCases {
            let item = NSMenuItem(title: theme.label, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = theme.rawValue
            if theme == SettingsStore.shared.theme { item.state = .on }
            themeMenu.addItem(item)
        }
        let themeItem = NSMenuItem(title: "Theme: \(SettingsStore.shared.theme.label)", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        // ── Launch at Startup ──
        let startupItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleStartup(_:)),
            keyEquivalent: ""
        )
        startupItem.state = SettingsStore.shared.launchAtStartup ? .on : .off
        startupItem.target = self
        menu.addItem(startupItem)

        menu.addItem(NSMenuItem.separator())

        // ── About ──
        menu.addItem(withTitle: "About RunCatX", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        // ── Quit ──
        menu.addItem(withTitle: "Quit RunCatX", action: #selector(quitApp), keyEquivalent: "q")

        statusItem.menu = menu

        // Live update system info + titles every 0.8s
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            sysInfo.title = String(
                format: "CPU: %.1f%%  |  Mem: %.1f%% (%.1f/%.0f GB)  |  Disk: %.1f%% (%.1f/%.0f GB)",
                self.monitor.cpuUsage,
                self.monitor.memoryUsage, self.monitor.memoryUsedGB, self.monitor.memoryTotalGB,
                self.monitor.diskUsage, self.monitor.diskUsedGB, self.monitor.diskTotalGB
            )

            // Update submenu titles
            skinItem.title = "Skin: \(self.skinManager.currentSkin.label)"
            srcItem.title = "Speed By: \(SettingsStore.shared.speedSource.label)"
            fpsItem.title = "Max FPS: \(SettingsStore.shared.fpsLimit.label)"
            themeItem.title = "Theme: \(SettingsStore.shared.theme.label)"

            // Update title with speed indicator
            let fps = self.animator.framesPerSecond
            let label: String
            if fps < 1  { label = "💤 Sleeping" }
            else if fps < 5  { label = "🚶 Walking" }
            else if fps < 15 { label = "🏃 Jogging" }
            else if fps < 30 { label = "⚡ Running" }
            else { label = "💨 Blazing" }
            titleItem.title = "🐱 RunCatX — \(label) (\(String(format: "%.0f", fps)) fps)"

            // Update CPU text mode
            self.applyCPUTextMode()
        }
    }

    /// Show/hide CPU% text next to icon in menu bar.
    private func applyCPUTextMode() {
        if SettingsStore.shared.showCPUText {
            statusItem.button?.title = String(format: "%.0f%%", monitor.cpuUsage)
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    // MARK: - Actions

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let skin = SkinManager.Skin(rawValue: raw) else { return }
        skinManager.setSkin(skin)
        animator.changeSkin(to: skinManager.frames(for: skin))
        SettingsStore.shared.skin = raw
        updateCheckmarks(sender.menu, selectedRaw: raw)
    }

    @objc private func selectSpeedSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let src = SpeedSource(rawValue: raw) else { return }
        SettingsStore.shared.speedSource = src
        bindSpeedSource(src)
        updateCheckmarks(sender.menu, selectedRaw: raw)
    }

    @objc private func selectFPSLimit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let limit = FPSLimit(rawValue: raw) else { return }
        SettingsStore.shared.fpsLimit = limit
        animator.setFPSLimit(limit)
        updateCheckmarks(sender.menu, selectedRaw: raw)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ThemeMode(rawValue: raw) else { return }
        SettingsStore.shared.theme = mode
        applyTheme(mode)
        updateCheckmarks(sender.menu, selectedRaw: raw)
    }

    @objc private func toggleStartup(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        sender.state = newState ? .on : .off
        SettingsStore.shared.launchAtStartup = newState
        LaunchAtStartup.apply(newState)
    }

    @objc private func toggleShowCPUText(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        sender.state = newState ? .on : .off
        SettingsStore.shared.showCPUText = newState
        applyCPUTextMode()
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RunCatX"
        alert.informativeText = """
        🐱 A cute menu bar runner for macOS.

        CPU-driven animation speed.
        Built with ❤️ in Swift.

        Based on Kyome22's RunCat concept.
        Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "⭐ GitHub")
        alert.addButton(withTitle: "OK")
        alert.icon = statusItem.button?.image
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/krissss/RunCatX") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitApp(_ sender: Any?) { NSApplication.shared.terminate(nil) }

    // MARK: - Helpers

    private func updateCheckmarks(_ menu: NSMenu?, selectedRaw: String) {
        guard let items = menu?.items else { return }
        for item in items {
            if let raw = item.representedObject as? String {
                item.state = (raw == selectedRaw) ? .on : .off
            }
        }
    }
}

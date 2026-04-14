import AppKit
import Combine

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   LEFT CLICK  → Toggle CPU% text display (quick, one-tap action)
///   RIGHT CLICK → Full settings menu
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SystemMonitor(sampleInterval: 1.0)
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var tooltipTimer: Timer?
    private var menuUpdateTimer: Timer?

    // ── Stored menu item references (replaces objc_setAssociatedObject hack) ──
    private var miTitle: NSMenuItem?
    private var miSysInfo: NSMenuItem?
    private var miSkin: NSMenuItem?
    private var miSrc: NSMenuItem?
    private var miFPS: NSMenuItem?
    private var miTheme: NSMenuItem?

    // ── Menu state ──
    private var isMenuShowing = false

    func start() {
        // 1. Create animator (not started yet)
        let initialFrames = skinManager.frames()
        animator = CatAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback (zero overhead animation path)
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

        // 4. Wire speed source (Combine OK here — 1Hz only)
        bindSpeedSource(SettingsStore.shared.speedSource)

        // 5. Apply theme
        applyTheme(SettingsStore.shared.theme)

        // 6. Configure button with LEFT/RIGHT click handling
        setupButton()

        // 7. Build menu
        setupMenu()

        // 8. Start everything LAST
        monitor.start()
        animator.start()
        startPeriodicUpdates()
    }

    func stop() {
        monitor.stop()
        animator.stop()
        tooltipTimer?.invalidate(); tooltipTimer = nil
        menuUpdateTimer?.invalidate(); menuUpdateTimer = nil
    }

    func pause()  { animator.stop() }
    func resume() { animator.start() }

    // ═════════════════════════════════════════════════════════
    // MARK: - Button: Left Click = Quick Action, Right Click = Menu
    // ═════════════════════════════════════════════════════════

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = "RunCatX — Left-click: Toggle CPU% | Right-click: Menu"
        button.target = self
        button.action = #selector(handleButtonClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleButtonClick(_ sender: NSStatusBarButton?) {
        let event = NSApp.currentEvent
        switch event?.type {
        case .leftMouseUp:
            toggleCPUTextQuick()
        case .rightMouseUp:
            // Show settings menu (inline to avoid Swift 6 sending check)
            guard let button = statusItem.button else { return }
            isMenuShowing = true
            snapshotMenuData()
            statusItem.menu?.popUp(positioning: nil, at: .zero, in: button)
        default:
            break
        }
    }

    /// Quick toggle: flip CPU text mode without opening menu.
    private func toggleCPUTextQuick() {
        SettingsStore.shared.showCPUText.toggle()
        applyCPUTextMode()
        // Brief feedback: flash tooltip
        showBriefFeedback(SettingsStore.shared.showCPUText ? "CPU% shown" : "CPU% hidden")
    }

    /// Called when menu closes (via delegate/notification).
    private func menuDidClose() {
        isMenuShowing = false
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Brief Feedback Tooltip
    // ═════════════════════════════════════════════════════════

    /// Shows a brief tooltip notification that auto-dismisses after 0.8s.
    private func showBriefFeedback(_ message: String) {
        statusItem.button?.toolTip = "✅ \(message)"
        // Schedule restore on main queue
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.statusItem.button?.toolTip = "RunCatX — Left-click: Toggle CPU% | Right-click: Menu"
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Snapshot (freeze data while menu is open)
    // ═════════════════════════════════════════════════════════

    private var snapshotCPU: Double = 0
    private var snapshotMemUsage: Double = 0
    private var snapshotMemUsedGB: Double = 0
    private var snapshotMemTotalGB: Double = 0
    private var snapshotDiskUsage: Double = 0
    private var snapshotDiskUsedGB: Double = 0
    private var snapshotDiskTotalGB: Double = 0
    private var snapshotFPS: Double = 0

    /// Capture current values so menu shows stable data.
    private func snapshotMenuData() {
        snapshotCPU = monitor.cpuUsage
        snapshotMemUsage = monitor.memoryUsage
        snapshotMemUsedGB = monitor.memoryUsedGB
        snapshotMemTotalGB = monitor.memoryTotalGB
        snapshotDiskUsage = monitor.diskUsage
        snapshotDiskUsedGB = monitor.diskUsedGB
        snapshotDiskTotalGB = monitor.diskTotalGB
        snapshotFPS = animator.computeFPS()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Tooltip
    // ═════════════════════════════════════════════════════════

    private func updateTooltip() {
        guard !isMenuShowing else { return } // don't update while menu is up
        statusItem.button?.toolTip = String(
            format: "RunCatX\nCPU: %.1f%% | Mem: %.0f%% (%.1f/%.0f GB)\nLeft-click: Toggle CPU%%",
            monitor.cpuUsage,
            monitor.memoryUsage, monitor.memoryUsedGB, monitor.memoryTotalGB
        )
    }

    private func startPeriodicUpdates() {
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateTooltip()
        }
        // Menu display update — only when menu is NOT showing
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, !self.isMenuShowing else { return }
            self.updateMenuDisplay()
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Accessibility (VoiceOver)
    // ═════════════════════════════════════════════════════════

    private func updateAccessibilityLabel(_ fps: Double) {
        guard let button = statusItem.button else { return }
        button.setAccessibilityLabel(String(
            format: "RunCatX. CPU %.1f%%. %.0f fps.",
            monitor.cpuUsage, fps
        ))
        button.setAccessibilityRole(.image)
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
        animator.updateValue(monitor.valueForSource(source))
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme
    // ═════════════════════════════════════════════════════════

    private func applyTheme(_ mode: ThemeMode) {
        skinManager.setTheme(mode)
        animator.changeSkin(to: skinManager.frames())
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - CPU Text Mode
    // ═════════════════════════════════════════════════════════

    private func applyCPUTextMode() {
        if SettingsStore.shared.showCPUText {
            statusItem.button?.title = String(format: "%.0f%%", monitor.cpuUsage)
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Menu Setup (clean, compact, organized)
    // ═════════════════════════════════════════════════════════

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // ── Row 1: App title + live speed badge ──
        miTitle = NSMenuItem(title: "🐱 RunCatX", action: nil, keyEquivalent: "")
        miTitle?.isEnabled = false
        menu.addItem(miTitle!)

        // ── Row 2: System Info (compact, aligned) ──
        miSysInfo = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        miSysInfo?.isEnabled = false
        menu.addItem(miSysInfo!)

        menu.addItem(NSMenuItem.separator())

        // ── Row 3: Runner (skin picker with emoji) ──
        let skinMenu = NSMenu()
        for skin in SkinManager.Skin.allCases {
            let item = NSMenuItem(
                title: "\(skin.emoji) \(skin.label.capitalized)",
                action: #selector(selectSkin(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = skin.rawValue
            if skin == skinManager.currentSkin { item.state = .on }
            skinMenu.addItem(item)
        }
        miSkin = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        miSkin?.submenu = skinMenu
        menu.addItem(miSkin!)

        // ── Row 4: Speed Source ──
        let srcMenu = NSMenu()
        for src in SpeedSource.allCases {
            let item = NSMenuItem(
                title: src.label,
                action: #selector(selectSpeedSource(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = src.rawValue
            if src == SettingsStore.shared.speedSource { item.state = .on }
            srcMenu.addItem(item)
        }
        miSrc = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        miSrc?.submenu = srcMenu
        menu.addItem(miSrc!)

        // ── Row 5: Performance (FPS limit + theme grouped together) ──
        let perfMenu = NSMenu()

        // FPS Limit section
        let fpsHeader = NSMenuItem(title: "Max Frame Rate", action: nil, keyEquivalent: "")
        fpsHeader.isEnabled = false
        perfMenu.addItem(fpsHeader)

        for fps in FPSLimit.allCases {
            let item = NSMenuItem(
                title: fps.label,
                action: #selector(selectFPSLimit(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = fps.rawValue
            if fps == SettingsStore.shared.fpsLimit { item.state = .on }
            perfMenu.addItem(item)
        }

        perfMenu.addItem(NSMenuItem.separator())

        // Theme section
        let themeHeader = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        themeHeader.isEnabled = false
        perfMenu.addItem(themeHeader)

        for theme in ThemeMode.allCases {
            let item = NSMenuItem(
                title: "\(theme.emoji) \(theme.label)",
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            if theme == SettingsStore.shared.theme { item.state = .on }
            perfMenu.addItem(item)
        }

        let perfItem = NSMenuItem(title: "Performance ▸", action: nil, keyEquivalent: "")
        perfItem.submenu = perfMenu
        menu.addItem(perfItem)

        // ── Row 6: Toggles ──
        let startupItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleStartup(_:)),
            keyEquivalent: ""
        )
        startupItem.state = SettingsStore.shared.launchAtStartup ? .on : .off
        startupItem.target = self
        menu.addItem(startupItem)

        let textToggle = NSMenuItem(
            title: "Show CPU % in Menu Bar",
            action: #selector(toggleShowCPUText(_:)),
            keyEquivalent: "t"
        )  // ⌘T shortcut
        textToggle.keyEquivalentModifierMask = .command
        textToggle.state = SettingsStore.shared.showCPUText ? .on : .off
        textToggle.target = self
        menu.addItem(textToggle)

        menu.addItem(NSMenuItem.separator())

        // ── Row 7: About ──
        menu.addItem(withTitle: "About RunCatX", action: #selector(showAbout), keyEquivalent: ",")

        // ── Row 8: Quit ──
        menu.addItem(withTitle: "Quit RunCatX", action: #selector(quitApp), keyEquivalent: "q")

        statusItem.menu = menu

        // Initial display refresh
        updateMenuDisplay()
    }

    /// Refreshes dynamic menu content (called by timer, NOT while menu is showing).
    private func updateMenuDisplay() {
        let fps = animator.computeFPS()

        // Status badge
        let label: String
        if fps < 1  { label = "💤" }
        else if fps < 5  { label = "🚶" }
        else if fps < 15 { label = "🏃" }
        else if fps < 30 { label = "⚡" }
        else { label = "💨" }
        miTitle?.title = "🐱 RunCatX  \(label)"

        // System info (compact format)
        miSysInfo?.title = formattedSystemInfo(live: true)

        // Submenu titles
        miSkin?.title = "\(skinManager.currentSkin.emoji) \(skinManager.currentSkin.label.capitalized)"
        miSrc?.title = "Speed: \(SettingsStore.shared.speedSource.label)"

        // CPU text mode
        applyCPUTextMode()
    }

    /// Formats system info string. Uses frozen snapshot when menu is open.
    private func formattedSystemInfo(live: Bool) -> String {
        let cpu = live ? monitor.cpuUsage : snapshotCPU
        let mU = live ? monitor.memoryUsage : snapshotMemUsage
        let mUb = live ? monitor.memoryUsedGB : snapshotMemUsedGB
        let mTb = live ? monitor.memoryTotalGB : snapshotMemTotalGB
        let dU = live ? monitor.diskUsage : snapshotDiskUsage
        let dUb = live ? monitor.diskUsedGB : snapshotDiskUsedGB
        let dTb = live ? monitor.diskTotalGB : snapshotDiskTotalGB

        return String(
            format: "CPU %@  ·  Mem %@ (%.1f/%.0fG)  ·  Disk %@ (%.0f/%.0fG)",
            percentString(cpu),
            percentString(mU), mUb, mTb,
            percentString(dU), dUb, dTb
        )
    }

    /// Returns a fixed-width percentage string: "  3%", "12%", "100%"
    private func percentString(_ value: Double) -> String {
        String(format: "%5.1f%%", value)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Actions
    // ═════════════════════════════════════════════════════════

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let skin = SkinManager.Skin(rawValue: raw) else { return }
        skinManager.setSkin(skin)
        animator.changeSkin(to: skinManager.frames(for: skin))
        SettingsStore.shared.skin = raw
        updateCheckmarks(sender.menu, selectedRaw: raw)
        showBriefFeedback("Skin: \(skin.emoji) \(skin.label.capitalized)")
    }

    @objc private func selectSpeedSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let src = SpeedSource(rawValue: raw) else { return }
        SettingsStore.shared.speedSource = src
        bindSpeedSource(src)
        updateCheckmarks(sender.menu, selectedRaw: raw)
        showBriefFeedback("Speed: \(src.label)")
    }

    @objc private func selectFPSLimit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let limit = FPSLimit(rawValue: raw) else { return }
        SettingsStore.shared.fpsLimit = limit
        animator.setFPSLimit(limit)
        updateCheckmarks(sender.menu, selectedRaw: raw)
        showBriefFeedback("FPS cap: \(limit.label)")
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ThemeMode(rawValue: raw) else { return }
        SettingsStore.shared.theme = mode
        applyTheme(mode)
        updateCheckmarks(sender.menu, selectedRaw: raw)
        showBriefFeedback("\(mode.emoji) \(mode.label)")
    }

    @objc private func toggleStartup(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        sender.state = newState ? .on : .off
        SettingsStore.shared.launchAtStartup = newState
        LaunchAtStartup.apply(newState)
        showBriefFeedback(newState ? "Login: ON" : "Login: OFF")
    }

    @objc private func toggleShowCPUText(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        sender.state = newState ? .on : .off
        SettingsStore.shared.showCPUText = newState
        applyCPUTextMode()
        showBriefFeedback(newState ? "CPU% ON" : "CPU% OFF")
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RunCatX"
        alert.informativeText = """
        🐱 A cute menu bar runner for macOS

        Animation speed follows your CPU usage.
        The harder you work, the faster it runs!

        Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
        Build: Swift 6 • macOS 13+

        Based on Kyome22's RunCat concept
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "⭐ GitHub")
        alert.addButton(withTitle: "OK")
        // Use first frame as static icon (not random animation frame)
        let frames = skinManager.frames()
        alert.icon = frames.first
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

// ═══════════════════════════════════════════════════════════════
// MARK: - NSMenuDelegate (detect menu close)
// ═══════════════════════════════════════════════════════════════

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuShowing = true
        snapshotMenuData()
        // Override with frozen snapshot values
        miTitle?.title = "🐱 RunCatX  \(statusEmoji(for: snapshotFPS))"
        miSysInfo?.title = formattedSystemInfo(live: false)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuShowing = false
    }

    private func statusEmoji(for fps: Double) -> String {
        if fps < 1  { return "💤" }
        else if fps < 5  { return "🚶" }
        else if fps < 15 { return "🏃" }
        else if fps < 30 { return "⚡" }
        else { return "💨" }
    }
}

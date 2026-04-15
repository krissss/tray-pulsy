import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Owns NSStatusItem, wires SystemMonitor → Animator → icon.
///
/// Interaction model:
///   LEFT CLICK  → Toggle metric text display (quick, one-tap action)
///   RIGHT CLICK → Full settings menu
///
/// The displayed metric (CPU% or Memory%) automatically follows the current
/// `speedSource` setting — no manual switching needed.
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SystemMonitor(sampleInterval: SettingsStore.shared.sampleInterval.seconds)
    private var animator: CatAnimator!
    private let skinManager = SkinManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var tooltipTimer: Timer?
    private var menuUpdateTimer: Timer?

    // ── Stored menu item references (replaces objc_setAssociatedObject hack) ──
    private var miTitle: NSMenuItem?
    private var miSysInfo: NSMenuItem?
    private var settingsWindow: NSWindow?

    // Notification tokens for settings window changes
    private var settingsObservers: [NSObjectProtocol] = []

    // ── Menu state ──
    private var isMenuShowing = false

    func start() {
        // 1. Create animator (not started yet)
        let initialFrames = skinManager.frames()
        animator = CatAnimator(initialFrames: initialFrames)

        // 2. Wire direct callback (zero overhead animation path)
        //    NOTE: Only image + accessibility here — NO title/text updates.
        //          Metric text updates at 1Hz via bindSpeedSource (Combine),
        //          NOT at animation framerate (wasteful & causes jitter).
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

        // 9. Listen for settings window changes
        setupSettingsObservers()
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
        button.toolTip = "RunCatX — 左键：切换显示数值 | 右键：菜单"
        button.target = self
        button.action = #selector(handleButtonClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleButtonClick(_ sender: NSStatusBarButton?) {
        let event = NSApp.currentEvent
        switch event?.type {
        case .leftMouseUp:
            toggleMetricTextQuick()
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

    /// Quick toggle: flip metric text mode without opening menu.
    /// Automatically shows/hides the metric matching current speedSource.
    private func toggleMetricTextQuick() {
        SettingsStore.shared.showMetricText.toggle()
        applyMetricTextMode()
        let label = currentMetricLabel()
        showBriefFeedback(
            SettingsStore.shared.showMetricText ? "已显示 \(label)%" : "已隐藏 \(label)%"
        )
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
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.statusItem.button?.toolTip =
                "RunCatX — 左键：切换显示 | 右键：菜单"
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
    private var snapshotNetIn: Double = 0   // bytes/sec
    private var snapshotNetOut: Double = 0  // bytes/sec
    private var snapshotGPU: Double = 0
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
        snapshotNetIn = monitor.netSpeedIn
        snapshotNetOut = monitor.netSpeedOut
        snapshotGPU = monitor.gpuUsage
        snapshotFPS = animator.computeFPS()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Tooltip
    // ═════════════════════════════════════════════════════════

    private func updateTooltip() {
        let src = SettingsStore.shared.speedSource
        let metricVal = monitor.valueForSource(src)
        statusItem.button?.toolTip = String(
            format: "RunCatX\n%@: %.1f%% | 内存: %.0f%% (%.1f/%.0f GB)\n左键：切换 %@%%",
            src.label, metricVal,
            monitor.memoryUsage, monitor.memoryUsedGB, monitor.memoryTotalGB,
            src.label
        )
    }

    private func startPeriodicUpdates() {
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateTooltip()
        }
        // Menu display update — always updates, even while menu is showing
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateMenuDisplay()
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Accessibility (VoiceOver)
    // ═════════════════════════════════════════════════════════

    private func updateAccessibilityLabel(_ fps: Double) {
        guard let button = statusItem.button else { return }
        let src = SettingsStore.shared.speedSource
        let val = monitor.valueForSource(src)
        button.setAccessibilityLabel(String(
            format: "RunCatX. %@ %.1f%%. %.0f fps.",
            src.label, val, fps
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
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()  // 1Hz update — NOT per-frame
                }
                .store(in: &cancellables)
        case .memory:
            monitor.$memoryUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()  // 1Hz update — NOT per-frame
                }
                .store(in: &cancellables)
        case .disk:
            monitor.$diskUsage.receive(on: DispatchQueue.main)
                .sink { [weak self] v in
                    self?.animator.updateValue(source.normalizeForAnimation(v))
                    self?.applyMetricTextMode()  // 1Hz update — NOT per-frame
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
        // Feed normalized value to animator, keep raw for display
        animator.updateValue(source.normalizeForAnimation(monitor.valueForSource(source)))
        // Update "Show X%" menu item title to reflect new source
        refreshShowTextMenuItemTitle()
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme
    // ═════════════════════════════════════════════════════════

    private func applyTheme(_ mode: ThemeMode) {
        skinManager.setTheme(mode)
        animator.changeSkin(to: skinManager.frames())
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Metric Text Mode (dynamic: CPU% or Memory%)
    // ═════════════════════════════════════════════════════════

    /// Returns the human-readable label for the current speed source metric.
    private func currentMetricLabel() -> String {
        SettingsStore.shared.speedSource.label
    }

    /// Returns the current metric value for display (reads from monitor).
    private func currentMetricValue() -> Double {
        monitor.valueForSource(SettingsStore.shared.speedSource)
    }

    /// Applies (or removes) the metric text overlay on the status bar item.
    /// Automatically shows CPU% or Memory% depending on `speedSource`.
    private func applyMetricTextMode() {
        if SettingsStore.shared.showMetricText {
            statusItem.button?.title = String(format: "%.0f%%", currentMetricValue())
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    /// Updates the "Show X% in Menu Bar" menu item title to match current source.
    // Note: Menu config moved to Settings window — this is kept for left-click toggle feedback.
    private func refreshShowTextMenuItemTitle() {
        // No-op: show text title is now managed by SettingsView
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Menu Setup (精简：标题 / 信息 / 设置 / 关于 / 退出)
    // ═════════════════════════════════════════════════════════

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // ── 标题 + 实时速度标识 ──
        miTitle = NSMenuItem(title: "🐱 RunCatX", action: nil, keyEquivalent: "")
        miTitle?.isEnabled = false
        menu.addItem(miTitle!)

        // ── 系统信息（实时刷新）──
        miSysInfo = NSMenuItem(title: "加载中…", action: nil, keyEquivalent: "")
        miSysInfo?.isEnabled = false
        menu.addItem(miSysInfo!)

        menu.addItem(NSMenuItem.separator())

        // ── 偏好设置 ──
        let settingsItem = NSMenuItem(
            title: "偏好设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // ── 关于 ──
        let aboutItem = NSMenuItem(
            title: "关于 RunCatX",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // ── 退出 ──
        menu.addItem(withTitle: "退出 RunCatX", action: #selector(quitApp), keyEquivalent: "q")

        statusItem.menu = menu

        // 初始显示
        updateMenuDisplay()
    }

    /// Refreshes dynamic menu content (called by timer, NOT while menu is showing).
    /// NOTE: Metric text (status bar title) is updated separately via
    ///       bindSpeedSource Combine pipeline at 1Hz — NOT here.
    private func updateMenuDisplay() {
        // Sync observable monitor for SwiftUI settings window
        ObservableMonitor.shared.sync(from: monitor)

        let fps = animator.computeFPS()

        // 状态标识
        let label: String
        if fps < 1  { label = "💤" }
        else if fps < 5  { label = "🚶" }
        else if fps < 15 { label = "🏃" }
        else if fps < 30 { label = "⚡" }
        else { label = "💨" }
        miTitle?.title = "🐱 RunCatX  \(label)"

        // 系统信息（紧凑格式）
        miSysInfo?.title = formattedSystemInfo(live: true)
    }

    /// Formats system info string. Primary metric (first position) follows speedSource.
    /// Uses frozen snapshot when menu is open.
    private func formattedSystemInfo(live: Bool) -> String {
        let src = SettingsStore.shared.speedSource
        let cpu   = live ? monitor.cpuUsage      : snapshotCPU
        let mU    = live ? monitor.memoryUsage    : snapshotMemUsage
        let mUb   = live ? monitor.memoryUsedGB   : snapshotMemUsedGB
        let mTb   = live ? monitor.memoryTotalGB  : snapshotMemTotalGB
        let dU    = live ? monitor.diskUsage      : snapshotDiskUsage
        let dUb   = live ? monitor.diskUsedGB     : snapshotDiskUsedGB
        let dTb   = live ? monitor.diskTotalGB    : snapshotDiskTotalGB
        let gpu   = live ? monitor.gpuUsage       : snapshotGPU
        let netIn  = live ? monitor.netSpeedIn    : snapshotNetIn
        let netOut = live ? monitor.netSpeedOut   : snapshotNetOut

        // Primary metric = whatever drives the animation
        let primaryLabel = src.label
        let primaryValue: Double
        switch src {
        case .cpu:     primaryValue = cpu
        case .memory:  primaryValue = mU
        case .disk:    primaryValue = dU
        case .gpu:     primaryValue = gpu
        }

        // Build string: primary first, then remaining metrics + net speed
        let secondary: String
        switch src {
        case .cpu:
            secondary = String(format: "Mem %@ (%.1f/%.0fG)  ·  Disk %@ (%.0f/%.0fG)",
                percentString(mU), mUb, mTb, percentString(dU), dUb, dTb)
        case .memory:
            secondary = String(format: "CPU %@  ·  Disk %@ (%.0f/%.0fG)",
                percentString(cpu), percentString(dU), dUb, dTb)
        case .disk:
            secondary = String(format: "CPU %@  ·  Mem %@ (%.1f/%.0fG)",
                percentString(cpu), percentString(mU), mUb, mTb)
        case .gpu:
            secondary = String(format: "CPU %@  ·  Mem %@ (%.1f/%.0fG)",
                percentString(cpu), percentString(mU), mUb, mTb)
        }

        let netStr = formatNetSpeed(inBytes: netIn, outBytes: netOut)
        return "\(primaryLabel) \(percentString(primaryValue))  ·  \(secondary)  ·  ⬇\(netStr.in) ⬆\(netStr.out)"
    }

    /// Returns a fixed-width percentage string: "  3%", "12%", "100%"
    private func percentString(_ value: Double) -> String {
        String(format: "%5.1f%%", value)
    }

    /// Formats bytes/sec into human-readable speed string.
    /// Returns (in: "1.2MB/s", out: "34KB/s") or ("—", "—") when idle.
    private func formatNetSpeed(inBytes: Double, outBytes: Double) -> (in: String, out: String) {
        let inStr = formatBPS(inBytes)
        let outStr = formatBPS(outBytes)
        return (in: inStr, out: outStr)
    }

    private func formatBPS(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 512 else { return "—" }   // < 0.5 KB/s → show dash
        let kb = bytesPerSec / 1024.0
        if kb < 1024 { return String(format: "%.0fKB/s", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1fMB/s", mb) }
        return String(format: "%.1fGB/s", mb / 1024.0)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Actions
    // ═════════════════════════════════════════════════════════

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "关于 RunCatX"
        alert.informativeText = """
        🐱 一只可爱的 macOS 菜单栏小猫

        动画速度跟随系统使用率。
        你越努力，它跑得越快！

        版本：\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
        构建：Swift 6 • macOS 13+

        灵感来自 Kyome22 的 RunCat
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "⭐ GitHub")
        alert.addButton(withTitle: "好的")
        let frames = skinManager.frames()
        alert.icon = frames.first
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/krissss/RunCatX") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RunCatX 偏好设置"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
        }
    }

    @objc private func quitApp(_ sender: Any?) { NSApplication.shared.terminate(nil) }

    // MARK: - Settings Window Notification Handlers

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

        settingsObservers.append(nc.addObserver(forName: .init("SettingsShowTextChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.applyMetricTextMode()
        })
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

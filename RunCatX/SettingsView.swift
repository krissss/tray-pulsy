import SwiftUI
import AppKit
import ServiceManagement
import Defaults

// ═══════════════════════════════════════════════════════════════
// MARK: - 设置变更通知
// ═══════════════════════════════════════════════════════════════

extension Notification.Name {
    static let skinChanged          = Notification.Name("com.runcatx.skinChanged")
    static let speedSourceChanged   = Notification.Name("com.runcatx.speedSourceChanged")
    static let fpsLimitChanged      = Notification.Name("com.runcatx.fpsLimitChanged")
    static let sampleIntervalChanged = Notification.Name("com.runcatx.sampleIntervalChanged")
    static let themeChanged         = Notification.Name("com.runcatx.themeChanged")
    static let metricTextChanged    = Notification.Name("com.runcatx.metricTextChanged")
}

/// 发送设置变更通知给 StatusBarController
private func postNotification(_ name: Notification.Name, object: Any? = nil) {
    NotificationCenter.default.post(name: name, object: object)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 设置窗口 (NavigationSplitView)
// ═══════════════════════════════════════════════════════════════
//
// macOS 标准三栏布局：Sidebar（导航）+ Detail（内容）
// 点击菜单栏图标打开此窗口。

struct SettingsView: View {
    @StateObject private var monitor = ObservableMonitor.shared
    @Default(.skin) private var skin
    @Default(.speedSource) private var speedSource
    @Default(.fpsLimit) private var fpsLimit
    @Default(.theme) private var theme
    @Default(.showMetricText) private var showMetricText
    @Default(.sampleInterval) private var sampleInterval
    @Default(.launchAtStartup) private var launchAtStartup

    @State private var selection: SettingsSection = .overview

    var body: some View {
        NavigationSplitView {
            // ── Sidebar ──
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .listStyle(.sidebar)
        } detail: {
            // ── Detail ──
            Group {
                switch selection {
                case .overview:   OverviewDetail()
                case .appearance: AppearanceDetail()
                case .performance: PerformanceDetail()
                case .general:    GeneralDetail()
                case .about:      AboutDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 520, idealHeight: 580)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Sidebar Sections
// ═══════════════════════════════════════════════════════════════

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview   = "overview"
    case appearance = "appearance"
    case performance = "performance"
    case general    = "general"
    case about      = "about"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:   return "概览"
        case .appearance: return "外观"
        case .performance: return "性能"
        case .general:    return "通用"
        case .about:      return "关于"
        }
    }

    var icon: String {
        switch self {
        case .overview:   return "gauge.with.dots.needle.bottom_50percent"
        case .appearance: return "paintpalette"
        case .performance: return "speedometer"
        case .general:    return "gearshape"
        case .about:      return "info.circle"
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 1. 概览 (Overview)
// ═══════════════════════════════════════════════════════════════

private struct OverviewDetail: View {
    @StateObject private var monitor = ObservableMonitor.shared
    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin

    @State private var previewTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── 猫动画预览 ──
                CatPreviewCard()

                Divider()

                // ── 实时系统监控 ──
                LiveMetricsCard()
            }
            .padding(24)
        }
        .navigationTitle("概览")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 猫动画预览卡片
// ═══════════════════════════════════════════════════════════════

private struct CatPreviewCard: View {
    @StateObject private var monitor = ObservableMonitor.shared
    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin
    @Default(.fpsLimit) private var fpsLimit

    @State private var frameIndex = 0
    @State private var previewTimer: Timer?
    @State private var displayedFPS: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("实时预览")
                .font(.headline)

            // 动画猫图标
            Group {
                if let frame = SkinManager.shared.frame(for: skin, frameIndex: frameIndex) {
                    Image(nsImage: frame)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 64, height: 64)

            // 当前数值 + FPS
            HStack(spacing: 24) {
                MetricBadge(
                    icon: speedSource.emoji,
                    label: speedSource.label,
                    value: String(format: "%.0f%%", monitor.valueForSource(speedSource))
                )
                MetricBadge(
                    icon: "film",
                    label: "帧率",
                    value: String(format: "%.0f", displayedFPS)
                )
            }

            Text("皮肤：\(SkinManager.Skin(rawValue: skin)?.label ?? skin)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .onAppear { startPreview() }
        .onDisappear { stopPreview() }
    }

    private func startPreview() {
        let source = speedSource
        let currentSkin = skin
        let rawValue = monitor.valueForSource(source)
        let normalized = source.normalizeForAnimation(rawValue)
        let interval = 0.2 / max(normalized / 5.0, 1.0)
        let clampedInterval = min(interval, fpsLimit.rateMultiplier * 0.05)
        let cappedFPS = 1.0 / clampedInterval
        displayedFPS = min(cappedFPS, 100)

        previewTimer?.invalidate()
        let skinEnum = SkinManager.Skin(rawValue: currentSkin) ?? .cat
        let totalFrames = SkinManager.shared.frames(for: skinEnum).count
        previewTimer = Timer.scheduledTimer(withTimeInterval: clampedInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                frameIndex = (frameIndex + 1) % totalFrames
            }
        }
    }

    private func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        frameIndex = 0
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 数值徽章
// ═══════════════════════════════════════════════════════════════

private struct MetricBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(icon).font(.title2)
            Text(value).font(.system(.body, design: .monospaced)).bold()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(minWidth: 70)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 实时系统信息卡片
// ═══════════════════════════════════════════════════════════════

private struct LiveMetricsCard: View {
    @StateObject private var monitor = ObservableMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统监控")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 12) {
                MetricRow(icon: "🧠", name: "CPU",     value: monitor.cpuUsage)
                MetricRow(icon: "🎮", name: "GPU",     value: monitor.gpuUsage)
                MetricRow(icon: "💾", name: "内存",    value: monitor.memoryUsage, detail: memoryDetail)
                MetricRow(icon: "💿", name: "磁盘",    value: monitor.diskUsage)
            }

            Divider()

            // 网络
            HStack {
                Text("🌐 网络")
                Spacer()
                Text("⬇\(formatSpeed(monitor.netSpeedIn))   ⬆\(formatSpeed(monitor.netSpeedOut))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private var memoryDetail: String {
        String(format: "%.1f / %.1f GB", monitor.memoryUsedGB, monitor.memoryTotalGB)
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1fMB/s", bytesPerSec / (1024 * 1024))
        } else {
            return String(format: "%.0fKB/s", bytesPerSec / 1024)
        }
    }
}

/// 单行指标
private struct MetricRow: View {
    let icon: String
    let name: String
    let value: Double
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(icon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f%%", value))
                        .font(.system(.callout, design: .monospaced))
                        .bold()
                    if let d = detail {
                        Text(d).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            // 迷你进度条
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(value / 100.0)),
                        alignment: .leading
                    )
            }
            .frame(height: 4)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 2. 外观 (Appearance)
// ═══════════════════════════════════════════════════════════════

private struct AppearanceDetail: View {
    @Default(.skin) private var skin
    @Default(.theme) private var theme
    @Default(.showMetricText) private var showMetricText

    var body: some View {
        Form {
            Section("皮肤") {
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(SkinManager.Skin.allCases, id: \.rawValue) { s in
                        SkinThumbnail(skin: s, isSelected: skin == s.rawValue)
                            .onTapGesture {
                                skin = s.rawValue
                                postNotification(.skinChanged, object: s.rawValue)
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("主题") {
                Picker("外观模式", selection: $theme) {
                    ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                        Text("\(mode.emoji) \(mode.displayName)").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { newTheme in
                    applyTheme(newTheme)
                    postNotification(.themeChanged, object: newTheme.rawValue)
                }
            }

            Section("菜单栏") {
                Toggle("显示数值文字", isOn: $showMetricText)
                    .onChange(of: showMetricText) { newVal in
                        postNotification(.metricTextChanged, object: newVal)
                    }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("外观")
        .padding(20)
    }

    private func applyTheme(_ mode: ThemeMode) {
        guard let dark = mode.isDarkOverride else {
            NSApp.appearance = nil
            return
        }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 皮肤缩略图
// ═══════════════════════════════════════════════════════════════

private struct SkinThumbnail: View {
    let skin: SkinManager.Skin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            // 缩略图预览
            if let frame = SkinManager.shared.frame(for: skin.rawValue, frameIndex: 0) {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: skin.iconName)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            Text(skin.label)
                .font(.caption)
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .frame(height: 72)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 3. 性能 (Performance)
// ═══════════════════════════════════════════════════════════════

private struct PerformanceDetail: View {
    @Default(.speedSource) private var speedSource
    @Default(.fpsLimit) private var fpsLimit
    @Default(.sampleInterval) private var sampleInterval

    var body: some View {
        Form {
            Section("速度来源") {
                Picker("动画驱动", selection: $speedSource) {
                    ForEach(SpeedSource.allCases, id: \.rawValue) { src in
                        Text("\(src.emoji) \(src.label)").tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: speedSource) { newSrc in
                    postNotification(.speedSourceChanged, object: newSrc.rawValue)
                }
            }

            Section("帧率上限") {
                Picker("最高帧率", selection: $fpsLimit) {
                    ForEach(FPSLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: fpsLimit) { newLimit in
                    postNotification(.fpsLimitChanged, object: newLimit.rateMultiplier)
                }
            }

            Section("采样间隔") {
                Picker("数据刷新频率", selection: $sampleInterval) {
                    ForEach(SampleInterval.allCases, id: \.rawValue) { si in
                        Text(si.displayName).tag(si)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: sampleInterval) { newSI in
                    postNotification(.sampleIntervalChanged, object: newSI.seconds)
                }
            }

            Section(footer: Text("间隔越短，动画响应越快，但 CPU 占用略高。")) {
                Text("当前采样：\(sampleInterval.displayName)")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("性能")
        .padding(20)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 4. 通用 (General)
// ═══════════════════════════════════════════════════════════════

private struct GeneralDetail: View {
    @Default(.launchAtStartup) private var launchAtStartup

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机自动启动", isOn: $launchAtStartup)
                    .onChange(of: launchAtStartup) { newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("通用")
        .padding(20)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("⚠️ Launch-at-login error: \(error)")
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 5. 关于 (About)
// ═══════════════════════════════════════════════════════════════

private struct AboutDetail: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App 图标 + 名称
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)

                VStack(spacing: 4) {
                    Text("RunCatX")
                        .font(.title.bold())
                    Text("版本 0.3.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                // 信息行
                VStack(spacing: 10) {
                    AboutRow(label: "开发者", value: "krissss")
                    AboutRow(label: "风格", value: "菜单栏猫咪动画")
                    AboutRow(label: "灵感来源", value: "Kyome22 / RunCat365")
                }

                Divider()

                // 退出按钮
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("退出 RunCatX", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("关于")
    }
}

private struct AboutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

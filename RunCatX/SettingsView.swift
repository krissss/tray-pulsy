import SwiftUI
import AppKit
import ServiceManagement

// ═══════════════════════════════════════════════════════════════
// MARK: - 设置窗口 (SwiftUI)
// ═══════════════════════════════════════════════════════════════

/// 点击菜单栏图标直接打开此窗口。
/// 所有配置项 + 实时系统信息 + 关于/退出 都在这里。
struct SettingsView: View {
    @StateObject private var monitor = ObservableMonitor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var previewSkin = ""
    @State private var previewSourceRaw = "cpu"
    @State private var previewFPSRaw = "40fps"
    @State private var previewIntervalRaw = "1s"
    @State private var previewThemeRaw = "system"
    @State private var previewShowText = false
    @State private var previewStartup = false

    // 系统信息刷新 timer
    @State private var sysInfoTimer: Timer?

    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ══ 预览卡 ══
                    PreviewCard(source: currentSource, skin: previewSkin)

                    // ══ 系统信息（实时） ══
                    SystemInfoCard()

                    // ══ 皮肤 ══
                    SectionCard(title: "皮肤", icon: "pawprint.fill") {
                        SkinGrid(selected: $previewSkin)
                    }

                    // ══ 速度来源 ══
                    SectionCard(title: "速度来源", icon: "gauge.with.dots.needle.bottom_50percent") {
                        HStack(spacing: 8) {
                            ForEach(SpeedSource.allCases, id: \.rawValue) { src in
                                SourceChip(
                                    source: src,
                                    isSelected: previewSourceRaw == src.rawValue
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) {
                                    previewSourceRaw = src.rawValue
                                    applySource(src)
                                }}
                            }
                            Spacer()
                        }
                    }

                    // ══ 性能 ══
                    SectionCard(title: "性能", icon: "speedometer") {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("帧率上限").font(.caption).foregroundColor(.secondary)
                                Picker("", selection: $previewFPSRaw) {
                                    ForEach(FPSLimit.allCases.map(\.label), id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 80)
                                .onChange(of: previewFPSRaw) { newVal in
                                    if let fps = FPSLimit(rawValue: newVal) {
                                        store.fpsLimit = fps
                                        postNotification("SettingsFPSLimitChanged", object: fps)
                                    }
                                }
                            }

                            VStack(alignment: .leading) {
                                Text("采样间隔").font(.caption).foregroundColor(.secondary)
                                Picker("", selection: $previewIntervalRaw) {
                                    ForEach(SampleInterval.allCases.map(\.label), id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 90)
                                .onChange(of: previewIntervalRaw) { newVal in
                                    if let si = SampleInterval(rawValue: newVal) {
                                        store.sampleInterval = si
                                        postNotification("SettingsSampleIntervalChanged", object: si.seconds)
                                    }
                                }
                            }

                            Spacer()
                        }
                    }

                    // ══ 外观 ══
                    SectionCard(title: "外观", icon: "paintbrush") {
                        HStack(spacing: 10) {
                            ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                                ThemeChip(
                                    mode: mode,
                                    isSelected: previewThemeRaw == mode.rawValue
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) {
                                    previewThemeRaw = mode.rawValue
                                    applyTheme(mode)
                                }}
                            }
                            Spacer()
                        }
                    }

                    // ══ 选项 ══
                    SectionCard(title: "选项", icon: "slider.horizontal.3") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledToggle(
                                title: "在菜单栏显示数值",
                                subtitle: "在图标旁显示当前 \(currentSource.label)% 数值",
                                isOn: $previewShowText
                            )
                            .onChange(of: previewShowText) { on in
                                store.showMetricText = on
                                postNotification("SettingsShowTextChanged", object: nil)
                            }

                            LabeledToggle(
                                title: "开机自启",
                                subtitle: "登录时自动启动 RunCatX",
                                isOn: $previewStartup
                            )
                            .onChange(of: previewStartup) { on in
                                store.launchAtStartup = on
                                applyStartup(on)
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    // ══ 关于 ══
                    SectionCard(title: "关于", icon: "info.circle") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("版本").foregroundColor(.secondary)
                                Spacer()
                                Text("0.2.0").fontWeight(.medium)
                            }
                            HStack {
                                Text("开发者").foregroundColor(.secondary)
                                Spacer()
                                Text("krissss")
                            }
                            HStack(alignment: .top) {
                                Text("说明").foregroundColor(.secondary)
                                Spacer()
                                Text("macOS 菜单栏猫咪动画\n基于 Kyome22 的 RunCat 重写")
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .font(.callout)
                    }

                    // ══ 退出按钮 ══
                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "power")
                            Text("退出 RunCatX")
                            Spacer()
                        }
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                }  // end VStack sections
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }  // end ScrollView

        }  // end outer VStack
        .frame(width: 440, height: 700)
        .onAppear {
            previewSkin = store.skin
            previewSourceRaw = store.speedSource.rawValue
            previewFPSRaw = store.fpsLimit.rawValue
            previewIntervalRaw = store.sampleInterval.rawValue
            previewThemeRaw = store.theme.rawValue
            previewShowText = store.showMetricText
            previewStartup = store.launchAtStartup
        }
    }

    // MARK: - Helpers

    private var currentSource: SpeedSource {
        SpeedSource(rawValue: previewSourceRaw) ?? .cpu
    }

    private func applySource(_ src: SpeedSource) {
        store.speedSource = src
        postNotification("SettingsSpeedSourceChanged", object: src)
    }

    private func applyTheme(_ mode: ThemeMode) {
        store.theme = mode
        postNotification("SettingsThemeChanged", object: mode)
    }

    private func applyStartup(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                try on ? service.register() : service.unregister()
            } catch {
                print("⚠️ 开机自启设置失败: \(error)")
            }
        }
    }

    /// Post a notification for StatusBarController to pick up.
    private func postNotification(_ name: String, object: Any? = nil) {
        NotificationCenter.default.post(name: .init(name), object: object)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 系统信息卡片（实时数据）
// ═══════════════════════════════════════════════════════════════

struct SystemInfoCard: View {
    @StateObject private var monitor = ObservableMonitor.shared

    var body: some View {
        SectionCard(title: "系统信息", icon: "desktopcomputer") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], alignment: .leading, spacing: 10) {

                MetricRow(label: "CPU", value: monitor.cpuUsage, unit: "%", emoji: "🧠", color: .blue)
                MetricRow(label: "GPU", value: monitor.gpuUsage, unit: "%", emoji: "🎮", color: .pink)
                MetricRow(label: "内存", value: monitor.memoryUsage, unit: "%", emoji: "💾", color: .purple)
                MetricRow(label: "磁盘", value: monitor.diskUsage, unit: "%", emoji: "💿", color: .orange)
            }

            Divider().padding(.vertical, 4)

            // 网络 + 内存详情
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("网络").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Label(formatBPS(monitor.netSpeedIn), systemImage: "arrow.down.circle")
                        Label(formatBPS(monitor.netSpeedOut), systemImage: "arrow.up.circle")
                    }
                    .font(.system(.caption, design: .monospaced))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("内存用量").font(.caption).foregroundColor(.secondary)
                    Text(String(format: "%.1f / %.0f GB",
                                monitor.memoryUsedGB,
                                monitor.memoryTotalGB))
                    .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private func formatBPS(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 512 else { return "—" }
        let kb = bytesPerSec / 1024.0
        if kb < 1024 { return String(format: "%.0fKB/s", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1fMB/s", mb)
    }
}

/// 单个指标行：emoji + 名称 + 大数字 + 单位
struct MetricRow: View {
    let label: String
    let value: Double
    let unit: String
    let emoji: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(y: -1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 预览卡片（带动画猫）
// ═══════════════════════════════════════════════════════════════

struct PreviewCard: View {
    let source: SpeedSource
    let skin: String
    @State private var frameIndex: Int = 0
    @State private var previewTimer: Timer?
    @StateObject private var monitor = ObservableMonitor.shared

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))

                VStack(spacing: 6) {
                    // 动画猫预览
                    Image(nsImage: currentFrame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)

                    // 当前值 + FPS
                    HStack(spacing: 12) {
                        Text("\(source.emoji) \(source.label): \(String(format: "%.1f", monitor.valueForSource(source)))%")
                            .font(.system(.body, design: .monospaced))
                        Text("~\(String(format: "%.0f", computedFPS))fps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 110)
        }
        .onAppear { startPreview() }
        .onDisappear { stopPreview() }
        .onChange(of: skin) { _ in restartPreview() }
    }

    private var currentFrame: NSImage {
        if let s = SkinManager.Skin(rawValue: skin) {
            return SkinManager.shared.frame(for: s.rawValue, frameIndex: frameIndex) ?? NSImage(size: NSSize(width: 32, height: 32))
        }
        return SkinManager.shared.frame(for: "cat", frameIndex: frameIndex) ?? NSImage(size: NSSize(width: 32, height: 32))
    }

    /// 模拟 CatAnimator 公式计算预览 FPS
    private var computedFPS: Double {
        let val = monitor.valueForSource(source)
        let clamped = max(1.0, min(20.0, val / 5.0))
        guard clamped > 0 else { return 0 }
        return (1.0 / (0.2 / clamped)) * 1.0  // rateMultiplier=1 for display
    }

    private func startPreview() {
        let val = monitor.valueForSource(source)
        let clamped = max(1.0, min(20.0, val / 5.0))
        let interval = 0.2 / clamped

        previewTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let frames = SkinManager.shared.frames(
                for: SkinManager.Skin(rawValue: skin) ?? .cat
            )
            guard !frames.isEmpty else { return }
            frameIndex = (frameIndex + 1) % frames.count
        }
    }

    private func stopPreview() {
        previewTimer?.invalidate(); previewTimer = nil
    }

    private func restartPreview() {
        stopPreview()
        frameIndex = 0
        startPreview()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 通用组件
// ═══════════════════════════════════════════════════════════════

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            content()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

/// 皮肤缩略图网格
struct SkinGrid: View {
    @Binding var selected: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(SkinManager.Skin.allCases, id: \.rawValue) { skin in
                SkinThumbnail(skin: skin, isSelected: selected == skin.rawValue)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) {
                        selected = skin.rawValue
                        SettingsStore.shared.skin = skin.rawValue
                        NotificationCenter.default.post(name: .init("SettingsSkinChanged"), object: nil)
                    }}
            }
        }
    }
}

/// 单个皮肤缩略图
struct SkinThumbnail: View {
    let skin: SkinManager.Skin
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                )

            Image(nsImage: SkinManager.shared.frame(for: skin.rawValue, frameIndex: 0) ?? NSImage(size: NSSize(width: 32, height: 32)))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
        }
        .frame(height: 44)
    }
}

/// 速度来源选择芯片
struct SourceChip: View {
    let source: SpeedSource
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(source.emoji)
            Text(source.label)
                .font(.callout.weight(isSelected ? .semibold : .regular))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3))
        )
        .foregroundColor(isSelected ? .white : .primary)
    }
}

/// 外观主题芯片
struct ThemeChip: View {
    let mode: ThemeMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(mode.emoji)
            Text(mode.label)
                .font(.callout.weight(isSelected ? .semibold : .regular))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3))
        )
        .foregroundColor(isSelected ? .white : .primary)
    }
}

/// 带标题和副标题的开关
struct LabeledToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

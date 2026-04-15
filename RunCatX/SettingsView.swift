import SwiftUI
import AppKit
import ServiceManagement

// ═══════════════════════════════════════════════════════════════
// MARK: - 设置窗口 (SwiftUI)
// ═══════════════════════════════════════════════════════════════

/// 托管在 NSWindow 中，从状态栏菜单打开。
/// 所有更改即时生效，无需"保存"按钮。
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

    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            // ── 标题栏 ──
            HStack {
                Text("RunCatX 偏好设置")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── 实时预览 ──
                    PreviewCard(source: currentSource, skin: previewSkin)

                    // ── 皮肤 ──
                    SectionCard(title: "皮肤", icon: "pawprint.fill") {
                        SkinGrid(selected: $previewSkin)
                    }

                    // ── 速度来源 ──
                    SectionCard(title: "速度来源", icon: "gauge.with.dots.needle.bottom.50percent") {
                        HStack(spacing: 8) {
                            ForEach(SpeedSource.allCases, id: \.rawValue) { src in
                                SourceChip(
                                    source: src,
                                    isSelected: previewSourceRaw == src.rawValue,
                                    currentValue: monitor.valueForSource(src)
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) {
                                    previewSourceRaw = src.rawValue
                                    applySource(src)
                                } }
                            }
                        }
                    }

                    // ── 性能 ──
                    SectionCard(title: "性能", icon: "speedometer") {
                        VStack(spacing: 10) {
                            PickerRow(
                                label: "帧率上限",
                                options: FPSLimit.allCases.map(\.label),
                                selected: $previewFPSRaw,
                                onChange: { raw in
                                    if let v = FPSLimit(rawValue: raw) {
                                        store.fpsLimit = v
                                        postNotification("SettingsFPSLimitChanged", object: v)
                                    }
                                }
                            )

                            PickerRow(
                                label: "采样间隔",
                                options: SampleInterval.allCases.map(\.label),
                                selected: $previewIntervalRaw,
                                onChange: { raw in
                                    if let v = SampleInterval(rawValue: raw) {
                                        store.sampleInterval = v
                                        postNotification("SettingsSampleIntervalChanged", object: v.seconds)
                                    }
                                }
                            )
                        }
                    }

                    // ── 外观 ──
                    SectionCard(title: "外观", icon: "paintpalette.fill") {
                        HStack(spacing: 8) {
                            ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                                ThemeChip(
                                    mode: mode,
                                    isSelected: previewThemeRaw == mode.rawValue
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) {
                                    previewThemeRaw = mode.rawValue
                                    applyTheme(mode)
                                } }
                            }
                        }
                    }

                    // ── 开关选项 ──
                    SectionCard(title: "选项", icon: "slider.horizontal.3") {
                        VStack(spacing: 8) {
                            ToggleRow(
                                title: "在菜单栏显示 \(currentSource.label)% 数值",
                                isOn: $previewShowText,
                                onChange: { val in
                                    store.showMetricText = val
                                    postNotification("SettingsShowTextChanged", object: val)
                                }
                            )
                            ToggleRow(
                                title: "开机自启",
                                isOn: $previewStartup,
                                onChange: { val in
                                    store.launchAtStartup = val
                                    applyStartup(val)
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // ── 底部 ──
            HStack {
                Text("所有更改即时生效")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 580)
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

    // MARK: - 计算属性

    private var currentSource: SpeedSource {
        SpeedSource(rawValue: previewSourceRaw) ?? .cpu
    }

    // MARK: - 应用变更

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

    private func postNotification(_ name: String, object: Any?) {
        NotificationCenter.default.post(name: Notification.Name(name), object: object)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 子视图
// ═══════════════════════════════════════════════════════════════

/// 卡片式分区容器。
private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundColor(.secondary)
            content
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

/// 实时预览卡：显示当前数值 + 动画猫。
private struct PreviewCard: View {
    let source: SpeedSource
    let skin: String
    @StateObject private var monitor = ObservableMonitor.shared

    @State private var frameIndex: Int = 0
    @State private var animationTimer: Timer?

    private var allFrames: [NSImage] {
        SkinManager.shared.frames(for: SkinManager.Skin(rawValue: skin) ?? .cat)
    }

    /// 与 CatAnimator 相同的帧间隔公式。
    private var frameInterval: TimeInterval {
        let rawValue = monitor.valueForSource(source)
        let normalized = source.normalizeForAnimation(rawValue)
        let clamped = max(1.0, min(20.0, normalized / 5.0))
        return 0.2 / clamped
    }

    var body: some View {
        VStack(spacing: 8) {
            if !allFrames.isEmpty {
                Image(nsImage: allFrames[frameIndex % allFrames.count])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
                    .onAppear { startAnimation() }
                    .onDisappear { stopAnimation() }
                    .onChange(of: skin) { _ in
                        frameIndex = 0
                        restartAnimation()
                    }
            } else {
                Image(systemName: "questionmark")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                    .frame(height: 48)
            }

            HStack(spacing: 8) {
                Text(String(format: "\(source.label): %.1f%%", monitor.valueForSource(source)))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundColor(.primary)

                Text(String(format: "%.0f帧/秒", 1.0 / frameInterval))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(skin.isEmpty ? "—" : skin.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - 动画生命周期

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: frameInterval,
            repeats: false,
            block: { _ in
                DispatchQueue.main.async {
                    self.frameIndex += 1
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                    self.startAnimation()
                }
            }
        )
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func restartAnimation() {
        stopAnimation()
        startAnimation()
    }
}

/// 皮肤缩略图网格。
private struct SkinGrid: View {
    @Binding var selected: String
    private let skins = SkinManager.Skin.allCases

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(skins, id: \.rawValue) { skin in
                SkinThumbnail(skin: skin, isSelected: selected == skin.rawValue)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) {
                        selected = skin.rawValue
                        SettingsStore.shared.skin = skin.rawValue
                    } }
            }
        }
    }
}

/// 单个皮肤缩略图。
private struct SkinThumbnail: View {
    let skin: SkinManager.Skin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let img = SkinManager.shared.frame(for: skin.rawValue, frameIndex: 0) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: skin.iconName)
                    .frame(width: 28, height: 28)
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            Text(skin.emoji)
                .font(.caption2)
        }
        .padding(4)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(6)
    }
}

/// 速度来源选择芯片。
private struct SourceChip: View {
    let source: SpeedSource
    let isSelected: Bool
    let currentValue: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(source.label)
                .font(.caption.bold())
            Text(String(format: "%.0f%%", currentValue))
                .font(.system(.caption2).monospacedDigit())
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3))
        .cornerRadius(6)
        .foregroundColor(isSelected ? .white : .primary)
    }
}

/// 外观主题选择芯片。
private struct ThemeChip: View {
    let mode: ThemeMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(mode.emoji)
                .font(.caption)
            Text(mode.label)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3))
        .cornerRadius(6)
        .foregroundColor(isSelected ? .white : .primary)
    }
}

/// 带标签的下拉选择行。
private struct PickerRow: View {
    let label: String
    let options: [String]
    @Binding var selected: String
    let onChange: (String) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Picker("", selection: Binding(
                get: { selected },
                set: { newValue in selected = newValue; onChange(newValue) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .pickerStyle(.menu)
        }
    }
}

/// 开关行。
private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in isOn = newValue; onChange(newValue) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

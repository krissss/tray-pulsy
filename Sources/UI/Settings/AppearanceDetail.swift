import Defaults
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - 皮肤 Tab
// ═══════════════════════════════════════════════════════════════

struct SkinDetail: View {
    @Environment(AppState.self) private var appState
    @Default(.skin) private var skin
    @Default(.externalSkinPath) private var externalSkinPath
    @Default(.pulsyColorTheme) private var pulsyColorTheme
    @Default(.pulsyWaveformStyle) private var pulsyWaveformStyle
    @Default(.pulsyLineWidth) private var pulsyLineWidth
    @Default(.pulsyGlowIntensity) private var pulsyGlowIntensity
    @Default(.pulsyAmplitudeSensitivity) private var pulsyAmplitudeSensitivity

    var body: some View {
        SettingsFormPage {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)], spacing: 10) {
                    ForEach(appState.skinManager.allSkins) { s in
                        Button {
                            skin = s.id
                        } label: {
                            SkinThumbnail(
                                skin: s,
                                isSelected: skin == s.id,
                                pulsyConfigToken: pulsyConfigToken
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n.skinLibraryHeader)
            }

            pulsyConfigSection()

            Section {
                HStack(alignment: .center, spacing: 12) {
                    externalSkinPathLabel
                        .frame(width: 92, alignment: .leading)
                    externalSkinPathControls
                        .layoutPriority(1)
                }

                if !externalSkinPath.isEmpty {
                    let expanded = (externalSkinPath as NSString).expandingTildeInPath
                    if !FileManager.default.fileExists(atPath: expanded) {
                        Label(L10n.skinPathNotFound, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text(L10n.skinExtHeader)
            } footer: {
                Text(L10n.skinExtInfo)
            }
        }
    }

    /// Show Pulsy config section when pulsy skin is selected.
    private var showPulsyConfig: Bool { skin == "pulsy" }

    private var pulsyConfigToken: String {
        "\(pulsyColorTheme.rawValue)-\(pulsyWaveformStyle.rawValue)-\(pulsyLineWidth)-\(pulsyGlowIntensity)-\(pulsyAmplitudeSensitivity)"
    }

    private var externalSkinPathLabel: some View {
        SettingsRowLabel(
            title: L10n.skinPathLabel,
            systemImage: "folder",
            color: .pink
        )
    }

    private var externalSkinPathControls: some View {
        HStack(spacing: 8) {
            TextField("", text: $externalSkinPath, prompt: Text(L10n.skinPathPrompt))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)
                .layoutPriority(1)
                .accessibilityLabel(L10n.skinPathLabel)
            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    externalSkinPath = url.path
                }
            } label: {
                Label(L10n.skinBrowse, systemImage: "folder.badge.plus")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Pulsy Configuration Section
// ═══════════════════════════════════════════════════════════════

private extension SkinDetail {
    @ViewBuilder
    func pulsyConfigSection() -> some View {
        if showPulsyConfig {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        PulsyThemeStrip(selectedTheme: pulsyColorTheme)
                        VStack(alignment: .leading, spacing: 6) {
                            Picker(L10n.pulsySettingsColorTheme, selection: $pulsyColorTheme) {
                                ForEach(PulsyColorTheme.allCases, id: \.self) { theme in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(nsColor: theme.iconColor))
                                            .frame(width: 10, height: 10)
                                        Text(theme.displayName)
                                    }
                                    .tag(theme)
                                }
                            }

                            Picker(L10n.pulsySettingsWaveform, selection: $pulsyWaveformStyle) {
                                ForEach(PulsyWaveformStyle.allCases, id: \.self) { style in
                                    Label(style.displayName, systemImage: style.systemImage)
                                        .tag(style)
                                }
                            }
                        }
                    }

                    Divider()

                    PulsySliderRow(
                        title: L10n.pulsySettingsLineWidth,
                        systemImage: "lineweight",
                        value: String(format: "%.1f", pulsyLineWidth),
                        sliderValue: $pulsyLineWidth,
                        range: 0.5...2.0,
                        step: 0.1
                    )

                    PulsySliderRow(
                        title: L10n.pulsySettingsGlowIntensity,
                        systemImage: "sparkles",
                        value: String(format: "%.1f", pulsyGlowIntensity),
                        sliderValue: $pulsyGlowIntensity,
                        range: 0...1.0,
                        step: 0.1
                    )

                    PulsySliderRow(
                        title: L10n.pulsySettingsAmplitudeSensitivity,
                        systemImage: "waveform.path.ecg",
                        value: String(format: "%.2f", pulsyAmplitudeSensitivity),
                        sliderValue: $pulsyAmplitudeSensitivity,
                        range: 0.2...1.0,
                        step: 0.05
                    )
                }
            } header: {
                Text(L10n.pulsySettingsHeader)
            }
        }
    }
}

private struct PulsyThemeStrip: View {
    let selectedTheme: PulsyColorTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(selectedTheme.gradientStops.enumerated()), id: \.offset) { _, color in
                Rectangle()
                    .fill(Color(nsColor: color))
            }
        }
        .frame(width: 56, height: 38)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Color(nsColor: selectedTheme.iconColor).opacity(0.25), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}

private struct PulsySliderRow: View {
    let title: String
    let systemImage: String
    let value: String
    @Binding var sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        SettingsInsetPanel(spacing: 9) {
            HStack(spacing: 10) {
                SettingsRowLabel(
                    title: title,
                    systemImage: systemImage,
                    color: .pink
                )
                Spacer()
                SettingsValueBadge(text: value, color: .pink)
            }
            SingleValueSlider(value: $sliderValue, range: range, step: step, color: .pink)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 指标 Tab
// ═══════════════════════════════════════════════════════════════

struct MetricsDetail: View {
    @Default(.thresholds) private var thresholds

    var body: some View {
        SettingsFormPage {
            Section {
                ForEach(MetricDisplayItem.allCases) { item in
                    MetricRowView(item: item)
                }
            } header: {
                Text(L10n.metricsHeader)
            } footer: {
                Text(L10n.metricsFooter)
            }
        }
    }
}

// MARK: - Metric Row (toggle + thresholds combined)

private struct MetricRowView: View {
    let item: MetricDisplayItem
    @Default(.speedSource) private var speedSource
    @Default(.metricMonitorItems) private var metricMonitorItems
    @Default(.metricDisplayItems) private var metricDisplayItems
    @Default(.thresholds) private var thresholds
    @Default(.spikeDeltas) private var spikeDeltas
    @State private var isAdvancedExpanded = false

    private var isMonitored: Bool {
        metricMonitorItems.contains(item)
    }

    private var mode: MetricManagementMode {
        if metricDisplayItems.contains(item) {
            return .menuBar
        }
        if metricMonitorItems.contains(item) {
            return .monitorOnly
        }
        return .off
    }

    private var modeBinding: Binding<MetricManagementMode> {
        Binding(
            get: { mode },
            set: { newMode in
                switch newMode {
                case .off:
                    metricMonitorItems.remove(item)
                    metricDisplayItems.remove(item)
                    if item.requiredMetric == speedSource.requiredMetric,
                       let nextSource = SpeedSource.firstAvailable(in: metricMonitorItems) {
                        speedSource = nextSource
                    }
                    withAnimation(ContainedExpansionMotion.layoutAnimation(expanding: false)) {
                        isAdvancedExpanded = false
                    }
                case .monitorOnly:
                    metricMonitorItems.insert(item)
                    metricDisplayItems.remove(item)
                case .menuBar:
                    metricMonitorItems.insert(item)
                    metricDisplayItems.insert(item)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricHeaderRow

            if isMonitored {
                VStack(spacing: 0) {
                    SettingsDisclosureButton(
                        title: L10n.metricsAdvancedSettings,
                        systemImage: "slider.horizontal.3",
                        isExpanded: isAdvancedExpanded,
                        color: Color(nsColor: item.accentColor)
                    ) {
                        isAdvancedExpanded.toggle()
                    }

                    ContainedExpansion(isExpanded: isAdvancedExpanded, topSpacing: 2) {
                        SettingsInsetPanel(spacing: 12) {
                            DualThresholdSlider(
                                title: L10n.metricsColorThresholdLabel,
                                description: L10n.metricsColorThresholdDescription,
                                warning: Binding(
                                    get: { thresholds[keyPath: item.thresholdKeyPath].warning },
                                    set: { thresholds[keyPath: item.thresholdKeyPath].warning = $0 }
                                ),
                                critical: Binding(
                                    get: { thresholds[keyPath: item.thresholdKeyPath].critical },
                                    set: { thresholds[keyPath: item.thresholdKeyPath].critical = $0 }
                                ),
                                range: sliderRange,
                                step: sliderStep,
                                formatLabel: valueLabel
                            )
                            if item.supportsSpikeDiagnostics, let deltaKeyPath = item.spikeDeltaKeyPath {
                                SingleThresholdSlider(
                                    label: L10n.metricsSpikeDeltaLabel,
                                    description: L10n.metricsSpikeDeltaDescription,
                                    value: Binding(
                                        get: { spikeDeltas[keyPath: deltaKeyPath] },
                                        set: { spikeDeltas[keyPath: deltaKeyPath] = $0 }
                                    ),
                                    range: spikeDeltaRange,
                                    step: spikeDeltaStep,
                                    formatLabel: valueLabel
                                )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    // MARK: - Slider helpers

    private var metricHeaderRow: some View {
        HStack(spacing: 12) {
            metricLabel
            Spacer(minLength: 16)
            modePicker
        }
    }

    private var metricLabel: some View {
        SettingsRowLabel(
            title: item.displayName,
            systemImage: item.chartIcon,
            color: Color(nsColor: item.accentColor)
        )
    }

    private var modePicker: some View {
        Picker(L10n.metricsModePickerLabel, selection: modeBinding) {
            ForEach(MetricManagementMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 220)
    }

    private var isPercent: Bool {
        switch item {
        case .cpu, .gpu, .memory, .disk: return true
        case .networkDown, .networkUp:   return false
        }
    }

    private var sliderRange: ClosedRange<Double> {
        isPercent ? 0...100 : 0...20_000_000
    }

    private var sliderStep: Double {
        isPercent ? 5 : 1_000_000
    }

    private var spikeDeltaRange: ClosedRange<Double> {
        isPercent ? 0...50 : 0...10_000_000
    }

    private var spikeDeltaStep: Double {
        isPercent ? 1 : 250_000
    }

    private func valueLabel(for bytesOrPercent: Double) -> String {
        if isPercent {
            return "\(Int(bytesOrPercent))%"
        }
        let mb = bytesOrPercent / 1_000_000
        if mb >= 1 {
            return String(format: "%.0fM", mb)
        }
        return "\(Int(bytesOrPercent / 1_000))K"
    }

}

private enum MetricManagementMode: String, CaseIterable, Identifiable {
    case off
    case monitorOnly
    case menuBar

    var id: Self { self }

    var label: String {
        switch self {
        case .off:         return L10n.metricsModeOff
        case .monitorOnly: return L10n.metricsModeMonitorOnly
        case .menuBar:     return L10n.metricsModeMenuBar
        }
    }
}

// MARK: - Threshold Sliders

private struct DualThresholdSlider: View {
    let title: String
    let description: String
    @Binding var warning: Double
    @Binding var critical: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatLabel: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    SettingsValueBadge(text: L10n.metricsWarningThreshold(formatLabel(warning)), color: .orange)
                    SettingsValueBadge(text: L10n.metricsCriticalThreshold(formatLabel(critical)), color: .red)
                }
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let warningX = xPosition(for: warning, width: width)
                let criticalX = xPosition(for: critical, width: width)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 7)

                    Capsule(style: .continuous)
                        .fill(.yellow.opacity(0.28))
                        .frame(width: max(criticalX - warningX, 0), height: 7)
                        .offset(x: warningX)

                    Capsule(style: .continuous)
                        .fill(.red.opacity(0.28))
                        .frame(width: max(width - criticalX, 0), height: 7)
                        .offset(x: criticalX)

                    ThresholdHandle(color: .yellow)
                        .position(x: warningX, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    warning = min(value(for: gesture.location.x, width: width), critical - step)
                                }
                        )

                    ThresholdHandle(color: .red)
                        .position(x: criticalX, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    critical = max(value(for: gesture.location.x, width: width), warning + step)
                                }
                        )
                }
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .frame(height: 22)
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * min(max(fraction, 0), 1)
    }

    private func value(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct SingleThresholdSlider: View {
    let label: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatLabel: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                SettingsValueBadge(text: "+\(formatLabel(value))", color: .accentColor)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let x = xPosition(for: value, width: width)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 7)

                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.28))
                        .frame(width: x, height: 7)

                    ThresholdHandle(color: .accentColor)
                        .position(x: x, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    value = steppedValue(for: gesture.location.x, width: width)
                                }
                        )
                }
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .frame(height: 22)
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * min(max(fraction, 0), 1)
    }

    private func steppedValue(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct SingleValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let x = xPosition(for: value, width: width)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 7)

                Capsule(style: .continuous)
                    .fill(color.opacity(0.28))
                    .frame(width: x, height: 7)

                ThresholdHandle(color: color)
                    .position(x: x, y: 11)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                value = steppedValue(for: gesture.location.x, width: width)
                            }
                    )
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .frame(height: 22)
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * min(max(fraction, 0), 1)
    }

    private func steppedValue(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct ThresholdHandle: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(.background)
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
    }
}

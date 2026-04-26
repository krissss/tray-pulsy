import Defaults
import Sliders
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
        GlassEffectContainer {
            Form {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)], spacing: 10) {
                        ForEach(appState.skinManager.allSkins) { s in
                            Button {
                                skin = s.id
                            } label: {
                                SkinThumbnail(skin: s, isSelected: skin == s.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(L10n.skinHeader)
                }

                pulsyConfigSection()

                Section {
                    HStack {
                        TextField(L10n.skinPathLabel, text: $externalSkinPath, prompt: Text(L10n.skinPathPrompt))
                            .textFieldStyle(.roundedBorder)
                        Button(L10n.skinBrowse) {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                externalSkinPath = url.path
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    if !externalSkinPath.isEmpty {
                        let expanded = (externalSkinPath as NSString).expandingTildeInPath
                        if FileManager.default.fileExists(atPath: expanded) {
                            Text(L10n.skinExtInfo)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Label(L10n.skinPathNotFound, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text(L10n.skinExtHeader)
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: externalSkinPath) {
            // AppState already observes .externalSkinPath and calls skinManager.reload()
        }
    }

    /// Show Pulsy config section when pulsy skin is selected.
    private var showPulsyConfig: Bool { skin == "pulsy" }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Pulsy Configuration Section
// ═══════════════════════════════════════════════════════════════

private extension SkinDetail {
    @ViewBuilder
    func pulsyConfigSection() -> some View {
        if showPulsyConfig {
            Section {
                // Color theme picker
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

                // Waveform style picker
                Picker(L10n.pulsySettingsWaveform, selection: $pulsyWaveformStyle) {
                    ForEach(PulsyWaveformStyle.allCases, id: \.self) { style in
                        Label(style.displayName, systemImage: style.systemImage)
                            .tag(style)
                    }
                }

                // Line width slider
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.pulsySettingsLineWidth)
                    ValueSlider(value: $pulsyLineWidth, in: 0.5...2.0, step: 0.1)
                        .valueSliderStyle(
                            HorizontalValueSliderStyle(
                                track: HorizontalTrack(
                                    view: Capsule().foregroundColor(.accentColor)
                                )
                                .background(Capsule().foregroundColor(.primary.opacity(0.15)))
                                .frame(height: 2),
                                thumb: Circle()
                                    .foregroundColor(.accentColor)
                                    .shadow(color: .black.opacity(0.15), radius: 1),
                                thumbSize: CGSize(width: 12, height: 12),
                                thumbInteractiveSize: CGSize(width: 24, height: 24),
                                options: .interactiveTrack
                            )
                        )
                    Text(String(format: "%.1f", pulsyLineWidth))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }

                // Glow intensity slider
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.pulsySettingsGlowIntensity)
                    ValueSlider(value: $pulsyGlowIntensity, in: 0...1.0, step: 0.1)
                        .valueSliderStyle(
                            HorizontalValueSliderStyle(
                                track: HorizontalTrack(
                                    view: Capsule().foregroundColor(.accentColor)
                                )
                                .background(Capsule().foregroundColor(.primary.opacity(0.15)))
                                .frame(height: 2),
                                thumb: Circle()
                                    .foregroundColor(.accentColor)
                                    .shadow(color: .black.opacity(0.15), radius: 1),
                                thumbSize: CGSize(width: 12, height: 12),
                                thumbInteractiveSize: CGSize(width: 24, height: 24),
                                options: .interactiveTrack
                            )
                        )
                    Text(String(format: "%.1f", pulsyGlowIntensity))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }

                // Amplitude sensitivity slider
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.pulsySettingsAmplitudeSensitivity)
                    ValueSlider(value: $pulsyAmplitudeSensitivity, in: 0.2...1.0, step: 0.05)
                        .valueSliderStyle(
                            HorizontalValueSliderStyle(
                                track: HorizontalTrack(
                                    view: Capsule().foregroundColor(.accentColor)
                                )
                                .background(Capsule().foregroundColor(.primary.opacity(0.15)))
                                .frame(height: 2),
                                thumb: Circle()
                                    .foregroundColor(.accentColor)
                                    .shadow(color: .black.opacity(0.15), radius: 1),
                                thumbSize: CGSize(width: 12, height: 12),
                                thumbInteractiveSize: CGSize(width: 24, height: 24),
                                options: .interactiveTrack
                            )
                        )
                    Text(String(format: "%.2f", pulsyAmplitudeSensitivity))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 指标 Tab
// ═══════════════════════════════════════════════════════════════

struct MetricsDetail: View {
    @Default(.metricDisplayItems) private var metricDisplayItems
    @Default(.thresholds) private var thresholds

    var body: some View {
        GlassEffectContainer {
            Form {
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
            .formStyle(.grouped)
        }
    }
}

// MARK: - Metric Row (toggle + thresholds combined)

private struct MetricRowView: View {
    let item: MetricDisplayItem
    @Default(.metricDisplayItems) private var metricDisplayItems
    @Default(.thresholds) private var thresholds

    private var isEnabled: Bool {
        metricDisplayItems.contains(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { on in
                    if on { metricDisplayItems.insert(item) }
                    else  { metricDisplayItems.remove(item) }
                }
            )) {
                Text(item.displayName)
            }
            if isEnabled {
                DualThresholdSlider(
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
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Slider helpers

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

// MARK: - Dual Threshold Slider (spacenation/swiftui-sliders)

private struct DualThresholdSlider: View {
    @Binding var warning: Double
    @Binding var critical: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatLabel: (Double) -> String

    private var rangeBinding: Binding<ClosedRange<Double>> {
        Binding(
            get: { warning...critical },
            set: { r in
                warning = r.lowerBound
                critical = r.upperBound
            }
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            RangeSlider(range: rangeBinding, in: range, step: step)
                .rangeSliderStyle(
                    HorizontalRangeSliderStyle(
                        track: HorizontalRangeTrack(
                            view: Capsule().foregroundColor(.yellow)
                        )
                        .background(Capsule().foregroundColor(.primary.opacity(0.15)))
                        .frame(height: 2),
                        lowerThumb: Circle()
                            .foregroundColor(.yellow)
                            .shadow(color: .black.opacity(0.15), radius: 1),
                        upperThumb: Circle()
                            .foregroundColor(.red)
                            .shadow(color: .black.opacity(0.15), radius: 1),
                        lowerThumbSize: CGSize(width: 10, height: 10),
                        upperThumbSize: CGSize(width: 10, height: 10),
                        lowerThumbInteractiveSize: CGSize(width: 20, height: 20),
                        upperThumbInteractiveSize: CGSize(width: 20, height: 20)
                    )
                )

            HStack {
                Text(formatLabel(warning))
                    .font(.caption).monospacedDigit().foregroundStyle(.yellow)
                Spacer()
                Text(formatLabel(critical))
                    .font(.caption).monospacedDigit().foregroundStyle(.red)
            }
        }
    }
}

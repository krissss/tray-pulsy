import Defaults
import Sliders
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - 皮肤 Tab
// ═══════════════════════════════════════════════════════════════

struct SkinDetail: View {
    @Default(.skin) private var skin
    @Default(.externalSkinPath) private var externalSkinPath
    private let skinManager = SkinManager.shared

    var body: some View {
        Form {
            Section {
                GlassEffectContainer {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)], spacing: 10) {
                    ForEach(skinManager.allSkins) { s in
                        Button {
                            skin = s.id
                        } label: {
                            SkinThumbnail(skin: s, isSelected: skin == s.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                }
            } header: {
                Text("皮肤")
            }

            Section {
                HStack {
                    TextField("路径", text: $externalSkinPath, prompt: Text("~/skins"))
                        .textFieldStyle(.roundedBorder)
                    Button("浏览") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            externalSkinPath = url.path
                        }
                    }
                }
                if !externalSkinPath.isEmpty {
                    let expanded = (externalSkinPath as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: expanded) {
                        Text("目录下的皮肤文件夹会自动加载，同名会覆盖内置皮肤")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Label("路径不存在", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("外部皮肤")
            }
        }
        .formStyle(.grouped)
        .onChange(of: externalSkinPath) {
            SkinManager.shared.reload()
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
        Form {
            Section {
                ForEach(MetricDisplayItem.allCases) { item in
                    MetricRowView(item: item)
                }
            } header: {
                Text("菜单栏指标")
            } footer: {
                Text("勾选要在菜单栏图标旁显示的指标，拖动滑块设置颜色阈值。")
            }
        }
        .formStyle(.grouped)
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

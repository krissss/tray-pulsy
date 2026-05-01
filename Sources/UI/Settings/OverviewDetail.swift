import Defaults
import SwiftUI

struct OverviewDetail: View {
    var body: some View {
        GlassEffectContainer {
            Form {
                Section {
                    SkinPreviewSection()
                }
                Section {
                    MetricsGrid()
                } header: {
                    HStack {
                        Text(L10n.overviewMonitorHeader)
                        Spacer()
                        Button {
                            guard let url = NSWorkspace.shared.urlForApplication(
                                withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(L10n.overviewActivityMonitor, systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Skin Preview

private struct SkinPreviewSection: View {
    @Environment(AppState.self) private var appState
    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin
    @Default(.fpsLimit) private var fpsLimit

    @State private var previewAnimator: TrayAnimator?
    @State private var currentFrame: NSImage?

    var body: some View {
        HStack(spacing: 24) {
            Group {
                if let currentFrame {
                    Image(nsImage: currentFrame)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .padding(12)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(L10n.accSkinPreview)

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.skinManager.skin(for: skin).displayName)
                    .font(.headline)
                HStack(spacing: 20) {
                    Label("\(Int(appState.systemMonitor.valueForSource(speedSource)))%", systemImage: speedSource.systemImage)
                    Label("\(Int(previewAnimator?.currentFPS ?? 0)) FPS", systemImage: "gauge.with.dots.needle.33percent")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear { setupAnimator() }
        .onDisappear { previewAnimator?.stop() }
        .onChange(of: skin) { setupAnimator() }
        .onChange(of: fpsLimit) { previewAnimator?.setFPSLimit(fpsLimit) }
    }

    private func setupAnimator() {
        previewAnimator?.stop()
        let skinInfo = appState.skinManager.skin(for: skin)
        let frames = appState.skinManager.frames(for: skinInfo)
        let animator = TrayAnimator(initialFrames: frames)
        animator.setFPSLimit(fpsLimit)
        animator.onFrameUpdate = { [weak animator] image in
            // Capture animator to keep it alive; self check prevents stale updates
            _ = animator
            MainActor.assumeIsolated { currentFrame = image }
        }
        let source = speedSource
        animator.updateValue(source.normalizeForAnimation(appState.systemMonitor.valueForSource(source)))
        animator.start()
        previewAnimator = animator
    }
}

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    @Environment(AppState.self) private var appState
    @Default(.thresholds) private var thresholds
    @Default(.historyDuration) private var historyDuration

    var body: some View {
        Group {
            let monitor = appState.systemMonitor
            let snapshots = appState.metricsHistory.allSnapshots()
            let timestamps = snapshots.map(\.timestamp)

            VStack(spacing: 0) {
                ForEach(Array(MetricDisplayItem.chartOrder.enumerated()), id: \.element) { index, item in
                    if index > 0 { Divider().padding(.leading, 40) }
                    MetricChartRow(
                        icon: item.chartIcon,
                        label: item.chartLabel,
                        valueText: item.formattedValue(from: monitor),
                        subtitle: item == .memory ? MetricDisplayItem.memoryDetailText(from: monitor) : nil,
                        values: snapshots.map { $0[keyPath: item.historyKeyPath] },
                        timestamps: timestamps,
                        color: Color(item.accentColor),
                        thresholds: item.thresholdZones(from: thresholds),
                        valueFormatter: item.formatChartValue,
                        chartHeight: 64,
                        timeSpan: historyDuration.seconds,
                        showCurrentValue: false
                    )
                }
            }
        }
    }
}

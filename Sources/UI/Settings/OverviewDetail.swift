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
    @State private var tick = 0

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
                        valueText: overviewValue(for: item, monitor: monitor),
                        subtitle: item == .memory ? memoryDetail : nil,
                        values: snapshots.map { $0[keyPath: item.historyKeyPath] },
                        timestamps: timestamps,
                        color: Color(item.accentColor),
                        thresholds: thresholdZones(for: item),
                        valueFormatter: item.formatChartValue,
                        chartHeight: 64,
                        timeSpan: historyDuration.seconds,
                        showCurrentValue: false
                    )
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick &+= 1
        }
    }

    private func overviewValue(for item: MetricDisplayItem, monitor: SystemMonitor) -> String {
        if item == .networkDown {
            let down = MetricDisplayItem.networkDown.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
            let up = MetricDisplayItem.networkUp.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
            return "↓\(down)/s  ↑\(up)/s"
        }
        return item.formatValue(from: monitor).trimmingCharacters(in: .whitespaces)
    }

    private func thresholdZones(for item: MetricDisplayItem) -> [(value: Double, color: Color)] {
        let t: MetricThresholds
        switch item {
        case .cpu:         t = thresholds.cpu
        case .gpu:         t = thresholds.gpu
        case .memory:      t = thresholds.memory
        case .disk:        t = thresholds.disk
        case .networkDown: t = thresholds.networkDown
        case .networkUp:   t = thresholds.networkUp
        }
        return [(value: t.critical, color: .red), (value: t.warning, color: .yellow)]
    }

    private var memoryDetail: String {
        let monitor = appState.systemMonitor
        let f = ByteCountFormatter(); f.countStyle = .memory
        let used = f.string(fromByteCount: Int64(monitor.memoryUsedGB * 1_073_741_824))
        let total = f.string(fromByteCount: Int64(monitor.memoryTotalGB * 1_073_741_824))
        return "\(used) / \(total)"
    }
}

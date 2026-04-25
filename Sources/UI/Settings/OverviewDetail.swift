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
    private var monitor = SystemMonitor.shared
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
                Text(SkinManager.shared.skin(for: skin).displayName)
                    .font(.headline)
                HStack(spacing: 20) {
                    Label("\(Int(monitor.valueForSource(speedSource)))%", systemImage: speedSource.systemImage)
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
        let skinInfo = SkinManager.shared.skin(for: skin)
        let frames = SkinManager.shared.frames(for: skinInfo)
        let animator = TrayAnimator(initialFrames: frames)
        animator.setFPSLimit(fpsLimit)
        animator.onFrameUpdate = { [weak animator] image in
            // Capture animator to keep it alive; self check prevents stale updates
            _ = animator
            MainActor.assumeIsolated { currentFrame = image }
        }
        let source = speedSource
        animator.updateValue(source.normalizeForAnimation(monitor.valueForSource(source)))
        animator.start()
        previewAnimator = animator
    }
}

// MARK: - Metric Row View

private struct OverviewMetricRow: View {
    let item: MetricDisplayItem
    let value: String
    let color: NSColor
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)

            Text(item.overviewName)
                .foregroundStyle(.secondary)
            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit().bold())
                .foregroundStyle(Color(color))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.overviewName) \(value)")
    }
}

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    private var monitor = SystemMonitor.shared
    @Default(.thresholds) private var thresholds
    @State private var tick = 0

    var body: some View {
        Group {
            VStack(spacing: 0) {
                ForEach(Array(percentItems.enumerated()), id: \.element) { index, item in
                    if index > 0 { Divider().padding(.leading, 40) }
                    OverviewMetricRow(
                        item: item,
                        value: item.formatValue(from: monitor).trimmingCharacters(in: .whitespaces),
                        color: item.color(forRawValue: item.rawValue(from: monitor), thresholds: thresholds),
                        detail: item == .memory ? memoryDetail : nil
                    )
                }
                Divider().padding(.leading, 40)

                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular, in: .circle)
                        .accessibilityHidden(true)
                    Text(L10n.overviewNetwork)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 16) {
                        let downItem = MetricDisplayItem.networkDown
                        let upItem = MetricDisplayItem.networkUp
                        Label(downItem.formatValue(from: monitor).trimmingCharacters(in: .whitespaces) + "/s", systemImage: "arrow.down")
                            .foregroundStyle(Color(downItem.color(forRawValue: downItem.rawValue(from: monitor), thresholds: thresholds)))
                        Label(upItem.formatValue(from: monitor).trimmingCharacters(in: .whitespaces) + "/s", systemImage: "arrow.up")
                            .foregroundStyle(Color(upItem.color(forRawValue: upItem.rawValue(from: monitor), thresholds: thresholds)))
                    }
                    .font(.system(.body, design: .rounded).monospacedDigit().bold())
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick &+= 1
        }
    }

    private var percentItems: [MetricDisplayItem] {
        [.cpu, .gpu, .memory, .disk]
    }

    private var memoryDetail: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let used = formatter.string(fromByteCount: Int64(monitor.memoryUsedGB * 1_073_741_824))
        let total = formatter.string(fromByteCount: Int64(monitor.memoryTotalGB * 1_073_741_824))
        return "\(used) / \(total)"
    }
}

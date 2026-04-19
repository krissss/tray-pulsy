import Defaults
import SwiftUI

struct OverviewDetail: View {
    var body: some View {
        Form {
            Section {
                SkinPreviewSection()
            }
            Section("系统监控") {
                MetricsGrid()
            }
        }
        .formStyle(.grouped)
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
            .accessibilityLabel("当前皮肤预览")

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

private struct MetricRowView: View {
    let icon: String
    let name: String
    let value: Double
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(name)
                .foregroundStyle(.secondary)
            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("\(value, specifier: "%.1f")%")
                .font(.system(.body, design: .rounded).monospacedDigit().bold())
                .foregroundStyle(value > 80 ? .red : value > 50 ? .orange : .primary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    private var monitor = SystemMonitor.shared
    @State private var tick = 0

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                MetricRowView(icon: SpeedSource.cpu.systemImage, name: "CPU", value: monitor.cpuUsage)
                Divider().padding(.leading, 34)
                MetricRowView(icon: SpeedSource.gpu.systemImage, name: "GPU", value: monitor.gpuUsage)
                Divider().padding(.leading, 34)
                MetricRowView(icon: SpeedSource.memory.systemImage, name: "内存", value: monitor.memoryUsage, detail: memoryDetail)
                Divider().padding(.leading, 34)
                MetricRowView(icon: SpeedSource.disk.systemImage, name: "磁盘", value: monitor.diskUsage)
                Divider().padding(.leading, 34)

                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text("网络")
                    Spacer()
                    HStack(spacing: 16) {
                        Label(formatSpeed(monitor.netSpeedIn), systemImage: "arrow.down")
                        Label(formatSpeed(monitor.netSpeedOut), systemImage: "arrow.up")
                    }
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("网络 下载\(formatSpeed(monitor.netSpeedIn)) 上传\(formatSpeed(monitor.netSpeedOut))")
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick &+= 1
        }
    }

    private var memoryDetail: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let used = formatter.string(fromByteCount: Int64(monitor.memoryUsedGB * 1_073_741_824))
        let total = formatter.string(fromByteCount: Int64(monitor.memoryTotalGB * 1_073_741_824))
        return "\(used) / \(total)"
    }

    private static let speedFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        Self.speedFormatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

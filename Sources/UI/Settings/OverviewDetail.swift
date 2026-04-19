import Defaults
import SwiftUI

struct OverviewDetail: View {
    var body: some View {
        Form {
            Section {
                CatPreviewSection()
            }
            Section("系统监控") {
                MetricsGrid()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cat Preview

private struct CatPreviewSection: View {
    private var monitor = SystemMonitor.shared
    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin
    @Default(.fpsLimit) private var fpsLimit

    @State private var frameIndex = 0
    @State private var previewTimer: Timer?
    @State private var displayedFPS: Double = 0
    @State private var previewFrames: [NSImage] = []

    var body: some View {
        HStack(spacing: 24) {
            Group {
                if previewFrames.isEmpty {
                    Image(systemName: "questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: previewFrames[frameIndex])
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 56, height: 56)
            .padding(12)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel("当前皮肤预览")

            VStack(alignment: .leading, spacing: 6) {
                Text(SkinManager.shared.allSkins.first(where: { $0.id == skin })?.displayName ?? skin)
                    .font(.headline)
                HStack(spacing: 20) {
                    Label("\(Int(monitor.valueForSource(speedSource)))%", systemImage: speedSource.systemImage)
                    Label("\(Int(displayedFPS)) FPS", systemImage: "gauge.with.dots.needle.33percent")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear { loadFramesAndStart() }
        .onDisappear { stopPreview() }
        .onChange(of: skin) { loadFramesAndStart() }
    }

    private func loadFramesAndStart() {
        let skinInfo = SkinManager.shared.allSkins.first(where: { $0.id == skin })
            ?? SkinManager.shared.allSkins[0]
        previewFrames = SkinManager.shared.frames(for: skinInfo)
        frameIndex = 0
        restartPreview()
    }

    private func restartPreview() {
        let source = speedSource
        let rawValue = monitor.valueForSource(source)
        let normalized = source.normalizeForAnimation(rawValue)
        let interval = 0.2 / max(normalized / 5.0, 1.0)
        let clampedInterval = min(interval, fpsLimit.rateMultiplier * 0.05)
        displayedFPS = min(1.0 / clampedInterval, 100)

        previewTimer?.invalidate()
        let totalFrames = previewFrames.count
        guard totalFrames > 0 else { return }
        previewTimer = Timer.scheduledTimer(withTimeInterval: clampedInterval, repeats: true) { _ in
            Task { @MainActor in
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

import SwiftUI
import Defaults

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
    private var monitor = ObservableMonitor.shared
    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin
    @Default(.fpsLimit) private var fpsLimit

    @State private var frameIndex = 0
    @State private var previewTimer: Timer?
    @State private var displayedFPS: Double = 0

    var body: some View {
        HStack(spacing: 24) {
            Group {
                if let frame = SkinManager.shared.frame(for: skin, frameIndex: frameIndex) {
                    Image(nsImage: frame)
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
            .background(.regularMaterial, in: .circle)

            VStack(alignment: .leading, spacing: 6) {
                Text(SkinManager.shared.allSkins.first(where: { $0.id == skin })?.displayName ?? skin)
                    .font(.headline)
                HStack(spacing: 20) {
                    Label("\(Int(monitor.valueForSource(speedSource)))%", systemImage: speedSource.emoji)
                    Label("\(Int(displayedFPS)) FPS", systemImage: "gauge.with.dots.needle.33percent")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear { startPreview() }
        .onDisappear { stopPreview() }
    }

    private func startPreview() {
        let source = speedSource
        let currentSkin = skin
        let rawValue = monitor.valueForSource(source)
        let normalized = source.normalizeForAnimation(rawValue)
        let interval = 0.2 / max(normalized / 5.0, 1.0)
        let clampedInterval = min(interval, fpsLimit.rateMultiplier * 0.05)
        displayedFPS = min(1.0 / clampedInterval, 100)

        previewTimer?.invalidate()
        let skinInfo = SkinManager.shared.allSkins.first(where: { $0.id == currentSkin })
            ?? SkinManager.shared.allSkins[0]
        let totalFrames = SkinManager.shared.frames(for: skinInfo).count
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

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    private var monitor = ObservableMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            metricRow(icon: SpeedSource.cpu.emoji, name: "CPU", value: monitor.cpuUsage)
            Divider().padding(.leading, 34)
            metricRow(icon: SpeedSource.gpu.emoji, name: "GPU", value: monitor.gpuUsage)
            Divider().padding(.leading, 34)
            metricRow(icon: SpeedSource.memory.emoji, name: "内存", value: monitor.memoryUsage, detail: memoryDetail)
            Divider().padding(.leading, 34)
            metricRow(icon: SpeedSource.disk.emoji, name: "磁盘", value: monitor.diskUsage)
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
        }
    }

    @ViewBuilder
    private func metricRow(icon: String, name: String, value: Double, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

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

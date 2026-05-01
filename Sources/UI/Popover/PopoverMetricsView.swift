import Defaults
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Popover Metrics View
// ═══════════════════════════════════════════════════════════════

/// Real-time metrics panel shown in the menu-bar popover.
struct PopoverMetricsView: View {
    let systemMonitor: SystemMonitor

    @Default(.thresholds) private var thresholds
    @Default(.historyDuration) private var historyDuration
    @State private var tick = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 4) {
            // Metrics grid — driven by MetricDisplayItem.chartOrder (same as Overview)
            let snapshots = systemMonitor.history.allSnapshots()
            let timestamps = snapshots.map(\.timestamp)

            ForEach(MetricDisplayItem.chartOrder, id: \.self) { item in
                MetricChartRow(
                    icon: item.chartIcon,
                    label: item.chartLabel,
                    valueText: metricValue(for: item),
                    subtitle: item == .memory ? memoryDetail : nil,
                    values: snapshots.map { $0[keyPath: item.historyKeyPath] },
                    timestamps: timestamps,
                    color: Color(item.accentColor),
                    thresholds: thresholdZones(for: item),
                    valueFormatter: item.formatChartValue,
                    chartHeight: 48, iconSize: 18, compact: true,
                    timeSpan: historyDuration.seconds,
                    showCurrentValue: false
                )
            }
        }
        .padding(14)
        .frame(width: 300)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    // MARK: - Helpers (same logic as OverviewDetail.MetricsGrid)

    private func metricValue(for item: MetricDisplayItem) -> String {
        if item == .networkDown {
            let down = MetricDisplayItem.networkDown.formatValue(from: systemMonitor).trimmingCharacters(in: .whitespaces)
            let up = MetricDisplayItem.networkUp.formatValue(from: systemMonitor).trimmingCharacters(in: .whitespaces)
            return "↓\(down)/s  ↑\(up)/s"
        }
        return item.formatValue(from: systemMonitor).trimmingCharacters(in: .whitespaces)
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
        let f = ByteCountFormatter(); f.countStyle = .memory
        let used = f.string(fromByteCount: Int64(systemMonitor.memoryUsedGB * 1_073_741_824))
        let total = f.string(fromByteCount: Int64(systemMonitor.memoryTotalGB * 1_073_741_824))
        return "\(used) / \(total)"
    }

}

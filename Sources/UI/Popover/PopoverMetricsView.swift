import Defaults
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Popover Metrics View
// ═══════════════════════════════════════════════════════════════

/// Real-time metrics panel shown in the menu-bar popover.
/// Re-renders are driven by SystemMonitor's @Observable properties (cpuUsage, memoryUsage, etc.)
/// which update on the main thread every tick — no Timer needed.
struct PopoverMetricsView: View {
    let systemMonitor: SystemMonitor

    @Default(.thresholds) private var thresholds
    @Default(.historyDuration) private var historyDuration

    var body: some View {
        VStack(spacing: 4) {
            // Metrics grid — driven by MetricDisplayItem.chartOrder (same as Overview)
            let snapshots = systemMonitor.history.allSnapshots()
            let timestamps = snapshots.map(\.timestamp)

            ForEach(MetricDisplayItem.chartOrder, id: \.self) { item in
                MetricChartRow(
                    icon: item.chartIcon,
                    label: item.chartLabel,
                    valueText: item.formattedValue(from: systemMonitor),
                    subtitle: item == .memory ? MetricDisplayItem.memoryDetailText(from: systemMonitor) : nil,
                    values: snapshots.map { $0[keyPath: item.historyKeyPath] },
                    timestamps: timestamps,
                    color: Color(item.accentColor),
                    thresholds: item.thresholdZones(from: thresholds),
                    valueFormatter: item.formatChartValue,
                    chartHeight: 48, iconSize: 18, compact: true,
                    timeSpan: historyDuration.seconds,
                    showCurrentValue: false
                )
            }
        }
        .padding(14)
        .frame(width: 300)
    }

}

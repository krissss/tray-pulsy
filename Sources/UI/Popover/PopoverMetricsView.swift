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
            let history = systemMonitor.history

            ForEach(MetricDisplayItem.chartOrder, id: \.self) { item in
                MetricChartRow(
                    icon: item.chartIcon,
                    label: item.chartLabel,
                    valueText: item.formattedValue(from: systemMonitor),
                    subtitle: item == .memory ? MetricDisplayItem.memoryDetailText(from: systemMonitor) : nil,
                    values: history.cachedValues(for: item.historyKeyPath),
                    timestamps: history.cachedTimestampArray(),
                    color: Color(item.accentColor),
                    thresholds: item.thresholdZones(from: thresholds),
                    valueFormatter: item.formatChartValue,
                    chartHeight: 48, iconSize: 18, compact: true,
                    timeSpan: historyDuration.seconds,
                    showCurrentValue: false
                )
            }

            Divider()
                .padding(.top, 6)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L10n.popoverQuit, systemImage: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 300)
    }

}

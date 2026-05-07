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
    @State private var cpuProcessMonitor = ProcessResourceMonitor(kind: .cpu)
    @State private var memoryProcessMonitor = ProcessResourceMonitor(kind: .memory)
    @State private var processNetworkMonitor = ProcessNetworkMonitor()
    @State private var expandedProcessSection: ProcessSection?

    var body: some View {
        VStack(spacing: 4) {
            // Metrics grid — driven by MetricDisplayItem.chartOrder (same as Overview)
            let history = systemMonitor.history

            ForEach(MetricDisplayItem.chartOrder, id: \.self) { item in
                switch item {
                case .cpu:
                    MetricDisclosureRow(
                        row: metricRow(for: item, history: history),
                        isExpanded: expansionBinding(for: .cpu),
                        helpText: L10n.popoverCPUProcessesToggle
                    ) {
                        ProcessResourceListView(
                            monitor: cpuProcessMonitor,
                            kind: .cpu,
                            header: L10n.popoverProcessCPUHeader
                        )
                    }
                case .memory:
                    MetricDisclosureRow(
                        row: metricRow(for: item, history: history),
                        isExpanded: expansionBinding(for: .memory),
                        helpText: L10n.popoverMemoryProcessesToggle
                    ) {
                        ProcessResourceListView(
                            monitor: memoryProcessMonitor,
                            kind: .memory,
                            header: L10n.popoverProcessMemoryHeader
                        )
                    }
                case .networkDown:
                    MetricDisclosureRow(
                        row: metricRow(for: item, history: history),
                        isExpanded: expansionBinding(for: .network),
                        helpText: L10n.popoverNetworkProcessesToggle
                    ) {
                        ProcessNetworkListView(monitor: processNetworkMonitor)
                    }
                default:
                    metricRow(for: item, history: history)
                }
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
        .frame(width: 320)
        .onChange(of: expandedProcessSection) {
            updateProcessMonitors()
        }
        .onDisappear {
            stopProcessMonitors()
        }
    }

    private func metricRow(for item: MetricDisplayItem, history: MetricsHistory) -> MetricChartRow {
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

    private func expansionBinding(for section: ProcessSection) -> Binding<Bool> {
        Binding(
            get: { expandedProcessSection == section },
            set: { isExpanded in expandedProcessSection = isExpanded ? section : nil }
        )
    }

    private func updateProcessMonitors() {
        stopProcessMonitors()
        switch expandedProcessSection {
        case .cpu:
            cpuProcessMonitor.start()
        case .memory:
            memoryProcessMonitor.start()
        case .network:
            processNetworkMonitor.start()
        case nil:
            break
        }
    }

    private func stopProcessMonitors() {
        cpuProcessMonitor.stop()
        memoryProcessMonitor.stop()
        processNetworkMonitor.stop()
    }
}

private enum ProcessSection {
    case cpu
    case memory
    case network
}

private struct MetricDisclosureRow<Row: View, Detail: View>: View {
    let row: Row
    @Binding var isExpanded: Bool
    let helpText: String
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    row
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 22)
                        .padding(.top, 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel(helpText)

            if isExpanded {
                detail()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }
}

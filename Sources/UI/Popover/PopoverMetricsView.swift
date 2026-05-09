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
    let openMainWindow: () -> Void

    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin
    @Default(.thresholds) private var thresholds
    @Default(.historyDuration) private var historyDuration
    @State private var cpuProcessMonitor = ProcessResourceMonitor(kind: .cpu)
    @State private var memoryProcessMonitor = ProcessResourceMonitor(kind: .memory)
    @State private var processNetworkMonitor = ProcessNetworkMonitor()
    @State private var expandedProcessSection: ProcessSection?

    var body: some View {
        VStack(spacing: 10) {
            // Metrics grid — driven by MetricDisplayItem.chartOrder (same as Overview)
            let history = systemMonitor.history

            PopoverHeader(
                skinName: skinDisplayName,
                speedSource: speedSource
            )

            VStack(spacing: 8) {
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
                        MetricStaticRow(row: metricRow(for: item, history: history))
                    }
                }
            }

            PopoverActionBar(
                openMainWindow: openMainWindow,
                quit: { NSApp.terminate(nil) }
            )
        }
        .padding(12)
        .frame(width: 336)
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
            valueText: metricValueText(for: item, history: history),
            subtitle: item == .memory ? MetricDisplayItem.memoryDetailText(from: systemMonitor) : nil,
            values: history.cachedValues(for: item.historyKeyPath),
            timestamps: history.cachedTimestampArray(),
            color: Color(item.accentColor),
            thresholds: item.thresholdZones(from: thresholds),
            valueFormatter: item.formatChartValue,
            chartHeight: 52, iconSize: 18, compact: true,
            timeSpan: historyDuration.seconds,
            showCurrentValue: false
        )
    }

    private var skinDisplayName: String {
        let trimmed = skin.split(separator: ".", maxSplits: 1).last.map(String.init) ?? skin
        return trimmed.isEmpty ? AppConstants.appName : trimmed
    }

    private func metricValueText(for item: MetricDisplayItem, history: MetricsHistory) -> String {
        guard let snapshot = history.lastSnapshot else {
            return item.formattedValue(from: systemMonitor)
        }

        switch item {
        case .cpu:
            return String(format: "%.0f%%", snapshot.cpuUsage)
        case .gpu:
            return String(format: "%.0f%%", snapshot.gpuUsage)
        case .memory:
            return String(format: "%.0f%%", snapshot.memoryUsage)
        case .disk:
            return String(format: "%.0f%%", snapshot.diskUsage)
        case .networkDown:
            let down = MetricDisplayItem.formatSpeed(snapshot.netSpeedIn).trimmingCharacters(in: .whitespaces)
            let up = MetricDisplayItem.formatSpeed(snapshot.netSpeedOut).trimmingCharacters(in: .whitespaces)
            return "↓\(down)/s  ↑\(up)/s"
        case .networkUp:
            return MetricDisplayItem.formatSpeed(snapshot.netSpeedOut).trimmingCharacters(in: .whitespaces)
        }
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

private struct PopoverHeader: View {
    let skinName: String
    let speedSource: SpeedSource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: speedSource.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(skinName)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text("\(L10n.perfSourceLabel): \(speedSource.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(AppConstants.appName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PopoverActionBar: View {
    let openMainWindow: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openMainWindow) {
                Label(L10n.popoverOpenMainWindow, systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 28)
            .help(L10n.popoverOpenMainWindow)

            Button(action: quit) {
                Label(L10n.popoverQuit, systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(.secondary)
            .help(L10n.popoverQuit)
        }
    }
}

private struct MetricStaticRow<Row: View>: View {
    let row: Row

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            row
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: 14, height: 22)
                .padding(.top, 1)
        }
    }
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
                        .frame(maxWidth: .infinity)
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

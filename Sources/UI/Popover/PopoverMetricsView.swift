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
    @Default(.metricMonitorItems) private var metricMonitorItems
    @State private var cpuProcessMonitor = ProcessResourceMonitor(kind: .cpu)
    @State private var memoryProcessMonitor = ProcessResourceMonitor(kind: .memory)
    @State private var processNetworkMonitor = ProcessNetworkMonitor()
    @State private var expandedProcessSection: ProcessSection?

    var body: some View {
        VStack(spacing: 10) {
            // Metrics grid — driven by monitored chart items (same as Overview)
            let history = systemMonitor.history
            let chartItems = MetricDisplayItem.monitoredChartItems(from: metricMonitorItems)

            PopoverHeader(
                skinName: skinDisplayName,
                speedSource: speedSource,
                openMainWindow: openMainWindow,
                quit: { NSApp.terminate(nil) }
            )

            VStack(spacing: 8) {
                ForEach(chartItems, id: \.self) { item in
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
                    case .networkDown, .networkUp:
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
        }
        .padding(12)
        .frame(width: 336)
        .onChange(of: expandedProcessSection) {
            updateProcessMonitors()
        }
        .onChange(of: metricMonitorItems) {
            reconcileExpandedProcessSection()
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
            timestamps: history.cachedTimestampArray(for: item.historyKeyPath),
            color: Color(item.accentColor),
            secondaryValues: secondaryValues(for: item, history: history),
            secondaryColor: secondaryColor(for: item),
            thresholds: item.thresholdZones(from: thresholds),
            valueFormatter: item.formatChartValue,
            chartHeight: 52, iconSize: 18, compact: true,
            timeSpan: historyDuration.seconds,
            showCurrentValue: false,
            primaryValuePrefix: primaryValuePrefix(for: item),
            secondaryValuePrefix: secondaryValuePrefix(for: item)
        )
    }

    private func secondaryValues(for item: MetricDisplayItem, history: MetricsHistory) -> [Double]? {
        guard item == .networkDown,
              metricMonitorItems.contains(.networkDown),
              metricMonitorItems.contains(.networkUp) else {
            return nil
        }
        return history.cachedValues(for: MetricDisplayItem.networkUp.historyKeyPath)
    }

    private func secondaryColor(for item: MetricDisplayItem) -> Color? {
        guard item == .networkDown,
              metricMonitorItems.contains(.networkDown),
              metricMonitorItems.contains(.networkUp) else {
            return nil
        }
        return .cyan
    }

    private func primaryValuePrefix(for item: MetricDisplayItem) -> String? {
        switch item {
        case .networkDown:
            return "↓"
        case .networkUp:
            return "↑"
        default:
            return nil
        }
    }

    private func secondaryValuePrefix(for item: MetricDisplayItem) -> String? {
        guard item == .networkDown,
              metricMonitorItems.contains(.networkDown),
              metricMonitorItems.contains(.networkUp) else {
            return nil
        }
        return "↑"
    }

    private var skinDisplayName: String {
        let trimmed = skin.split(separator: ".", maxSplits: 1).last.map(String.init) ?? skin
        return trimmed.isEmpty ? AppConstants.appName : trimmed
    }

    private func metricValueText(for item: MetricDisplayItem, history: MetricsHistory) -> String {
        guard let snapshot = history.lastSnapshot else {
            return item.formattedValue(from: systemMonitor, monitoredItems: metricMonitorItems)
        }
        return item.formattedValue(
            from: snapshot,
            fallback: systemMonitor,
            monitoredItems: metricMonitorItems
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

    private func reconcileExpandedProcessSection() {
        guard let expandedProcessSection else {
            stopProcessMonitors()
            return
        }
        guard canShowProcessSection(expandedProcessSection) else {
            stopProcessMonitors()
            self.expandedProcessSection = nil
            return
        }
        updateProcessMonitors()
    }

    private func canShowProcessSection(_ section: ProcessSection) -> Bool {
        switch section {
        case .cpu:
            return metricMonitorItems.contains(.cpu)
        case .memory:
            return metricMonitorItems.contains(.memory)
        case .network:
            return metricMonitorItems.contains(.networkDown) || metricMonitorItems.contains(.networkUp)
        }
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
    let openMainWindow: () -> Void
    let quit: () -> Void

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

            HStack(spacing: 6) {
                Button(action: openMainWindow) {
                    Label(L10n.popoverOpenMainWindow, systemImage: "macwindow")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(L10n.popoverOpenMainWindow)
                .accessibilityLabel(L10n.popoverOpenMainWindow)

                Button(action: quit) {
                    Label(L10n.popoverQuit, systemImage: "power")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help(L10n.popoverQuit)
                .accessibilityLabel(L10n.popoverQuit)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MetricStaticRow<Row: View>: View {
    let row: Row

    var body: some View {
        row
            .frame(maxWidth: .infinity)
    }
}

private struct MetricDisclosureRow<Row: View, Detail: View>: View {
    let row: Row
    @Binding var isExpanded: Bool
    let helpText: String
    @ViewBuilder let detail: () -> Detail
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(ContainedExpansionMotion.layoutAnimation(expanding: !isExpanded)) {
                    isExpanded.toggle()
                }
            } label: {
                row
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.secondary.opacity(isHovering || isExpanded ? 0.16 : 0), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel(helpText)
            .onHover { isHovering = $0 }

            ContainedExpansion(isExpanded: isExpanded, topSpacing: 6) {
                detail()
            }
        }
    }
}

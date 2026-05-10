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
                Section {
                    SpikeDiagnosticsSection()
                } header: {
                    HStack {
                        Text(L10n.spikeSectionHeader)
                        Spacer()
                        Button {
                            clearSpikeEvents()
                        } label: {
                            Label(L10n.spikeClear, systemImage: "trash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(spikeEvents.isEmpty)
                    }
                } footer: {
                    Text(L10n.spikeSectionFooter)
                }
            }
            .formStyle(.grouped)
        }
    }

    @Environment(AppState.self) private var appState

    private var spikeEvents: [MetricSpikeEvent] { appState.spikeEvents }

    private func clearSpikeEvents() {
        appState.clearSpikeEvents()
    }
}

// MARK: - Skin Preview

private struct SkinPreviewSection: View {
    @Environment(AppState.self) private var appState
    @Default(.speedSource) private var speedSource
    @Default(.skin) private var skin
    @Default(.fpsLimit) private var fpsLimit
    @Default(.metricMonitorItems) private var metricMonitorItems

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
                Text(appState.skinManager.skin(for: skin).displayName)
                    .font(.headline)
                HStack(spacing: 20) {
                    Label("\(Int(currentSourceValue))%", systemImage: speedSource.systemImage)
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
        .onChange(of: speedSource) { syncAnimatorValue() }
        .onChange(of: metricMonitorItems) { syncAnimatorValue() }
        .onChange(of: fpsLimit) { previewAnimator?.setFPSLimit(fpsLimit) }
    }

    private func setupAnimator() {
        previewAnimator?.stop()
        let skinInfo = appState.skinManager.skin(for: skin)
        let frames = appState.skinManager.frames(for: skinInfo)
        let animator = TrayAnimator(initialFrames: frames)
        animator.setFPSLimit(fpsLimit)
        animator.onFrameUpdate = { [weak animator] image in
            // Capture animator to keep it alive; self check prevents stale updates
            _ = animator
            MainActor.assumeIsolated { currentFrame = image }
        }
        animator.updateValue(currentNormalizedValue)
        animator.start()
        previewAnimator = animator
    }

    private func syncAnimatorValue() {
        previewAnimator?.updateValue(currentNormalizedValue)
    }

    private var currentSourceValue: Double {
        guard isSpeedSourceMonitored else { return 0 }
        return appState.systemMonitor.valueForSource(speedSource)
    }

    private var currentNormalizedValue: Double {
        guard isSpeedSourceMonitored else { return 0 }
        return speedSource.normalizeForAnimation(appState.systemMonitor.valueForSource(speedSource))
    }

    private var isSpeedSourceMonitored: Bool {
        metricMonitorItems.contains { $0.requiredMetric == speedSource.requiredMetric }
    }
}

// MARK: - Spike Diagnostics

private struct SpikeDiagnosticsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.spikeEvents.isEmpty {
            ContentUnavailableView(
                L10n.spikeEmptyTitle,
                systemImage: "waveform.path.ecg",
                description: Text(L10n.spikeEmptyDescription)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 8) {
                ForEach(appState.spikeEvents) { event in
                    SpikeEventCard(event: event)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SpikeEventCard: View {
    let event: MetricSpikeEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: event.metric.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(event.metric.accentColor)
                        .frame(width: 26, height: 26)
                        .background {
                            Circle().fill(event.metric.accentColor.opacity(0.12))
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.metric.label)
                            .font(.subheadline.weight(.semibold))
                        Text(String(format: L10n.spikeJumpFormat, event.metric.formatValue(event.previousValue), event.metric.formatValue(event.currentValue)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timeFormatter.string(from: event.timestamp))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("Δ \(event.metric.formatValue(event.delta))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(event.metric.accentColor)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 22)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.spikeProcessesTitle)

            if isExpanded {
                SpikeProcessListView(processes: event.processes, status: event.processStatus)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(event.metric.accentColor.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    @Environment(AppState.self) private var appState
    @Default(.thresholds) private var thresholds
    @Default(.historyDuration) private var historyDuration
    @Default(.metricMonitorItems) private var metricMonitorItems

    @State private var cpuProcessMonitor = ProcessResourceMonitor(kind: .cpu)
    @State private var memoryProcessMonitor = ProcessResourceMonitor(kind: .memory)
    @State private var processNetworkMonitor = ProcessNetworkMonitor()
    @State private var expandedProcessSection: OverviewProcessSection?

    var body: some View {
        Group {
            let monitor = appState.systemMonitor
            let history = appState.metricsHistory
            let chartItems = MetricDisplayItem.monitoredChartItems(from: metricMonitorItems)

            VStack(spacing: 8) {
                ForEach(Array(chartItems.enumerated()), id: \.element) { index, item in
                    if index > 0 { Divider().padding(.leading, 40) }
                    VStack(spacing: 8) {
                        MetricChartRow(
                            icon: item.chartIcon,
                            label: item.chartLabel,
                            valueText: item.formattedValue(from: monitor, monitoredItems: metricMonitorItems),
                            subtitle: item == .memory ? MetricDisplayItem.memoryDetailText(from: monitor) : nil,
                            values: history.cachedValues(for: item.historyKeyPath),
                            timestamps: history.cachedTimestampArray(for: item.historyKeyPath),
                            color: Color(item.accentColor),
                            thresholds: item.thresholdZones(from: thresholds),
                            valueFormatter: item.formatChartValue,
                            chartHeight: 64,
                            timeSpan: historyDuration.seconds,
                            showCurrentValue: false
                        )

                        MetricProcessDisclosure(
                            item: item,
                            isExpanded: expansionBinding(for: processSection(for: item))
                        ) {
                            processList(for: item)
                        }
                    }
                }
            }
        }
        .onAppear {
            updateProcessMonitors()
        }
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

    @ViewBuilder
    private func processList(for item: MetricDisplayItem) -> some View {
        switch item {
        case .cpu:
            ProcessResourceListView(
                monitor: cpuProcessMonitor,
                kind: .cpu,
                header: L10n.popoverProcessCPUHeader,
                title: L10n.popoverProcessTopProcesses
            )
        case .memory:
            ProcessResourceListView(
                monitor: memoryProcessMonitor,
                kind: .memory,
                header: L10n.popoverProcessMemoryHeader,
                title: L10n.popoverProcessTopProcesses
            )
        case .networkDown, .networkUp:
            ProcessNetworkListView(
                monitor: processNetworkMonitor,
                title: L10n.popoverNetworkTopProcesses
            )
        default:
            EmptyView()
        }
    }

    private func processSection(for item: MetricDisplayItem) -> OverviewProcessSection? {
        switch item {
        case .cpu:
            return .cpu
        case .memory:
            return .memory
        case .networkDown, .networkUp:
            return .network
        default:
            return nil
        }
    }

    private func expansionBinding(for section: OverviewProcessSection?) -> Binding<Bool> {
        Binding(
            get: { section != nil && expandedProcessSection == section },
            set: { isExpanded in expandedProcessSection = isExpanded ? section : nil }
        )
    }

    private func updateProcessMonitors() {
        stopProcessMonitors()
        switch expandedProcessSection {
        case .cpu:
            cpuProcessMonitor.start(limit: 5)
        case .memory:
            memoryProcessMonitor.start(limit: 5)
        case .network:
            processNetworkMonitor.start(limit: 5)
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

    private func canShowProcessSection(_ section: OverviewProcessSection) -> Bool {
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

private enum OverviewProcessSection {
    case cpu
    case memory
    case network
}

private struct MetricProcessDisclosure<Detail: View>: View {
    let item: MetricDisplayItem
    @Binding var isExpanded: Bool
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        if canShowProcesses {
            VStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Label(title, systemImage: "list.bullet.rectangle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 22)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)

                if isExpanded {
                    detail()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.leading, 40)
            .animation(.easeInOut(duration: 0.16), value: isExpanded)
        }
    }

    private var canShowProcesses: Bool {
        switch item {
        case .cpu, .memory, .networkDown, .networkUp:
            return true
        default:
            return false
        }
    }

    private var title: String {
        switch item {
        case .networkDown, .networkUp:
            return L10n.popoverNetworkTopProcesses
        default:
            return L10n.popoverProcessTopProcesses
        }
    }
}

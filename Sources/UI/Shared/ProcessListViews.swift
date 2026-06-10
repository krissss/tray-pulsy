import SwiftUI

struct ProcessResourceListView: View {
    let monitor: ProcessResourceMonitor
    let kind: ProcessResourceKind
    let header: String
    let title: String

    init(
        monitor: ProcessResourceMonitor,
        kind: ProcessResourceKind,
        header: String,
        title: String = L10n.popoverProcessTopProcesses
    ) {
        self.monitor = monitor
        self.kind = kind
        self.header = header
        self.title = title
    }

    var body: some View {
        ProcessListPanel(
            title: title,
            header: header,
            isSampling: monitor.isSampling,
            errorMessage: monitor.errorMessage,
            isEmpty: monitor.processes.isEmpty
        ) {
            ForEach(monitor.processes) { process in
                ProcessResourceRow(
                    process: process,
                    kind: kind,
                    isPinned: monitor.pinnedProcessIDs.contains(process.pid),
                    togglePinned: { monitor.togglePinnedProcess(process) },
                    terminateProcess: { monitor.terminateProcess(pid: process.pid) }
                )
            }
        }
    }
}

struct ProcessNetworkListView: View {
    let monitor: ProcessNetworkMonitor
    let title: String

    init(monitor: ProcessNetworkMonitor, title: String = L10n.popoverNetworkTopProcesses) {
        self.monitor = monitor
        self.title = title
    }

    var body: some View {
        ProcessListPanel(
            title: title,
            header: L10n.popoverNetworkProcessHeader,
            isSampling: monitor.isSampling,
            errorMessage: monitor.errorMessage,
            isEmpty: monitor.processes.isEmpty
        ) {
            ForEach(monitor.processes) { process in
                ProcessNetworkRow(
                    process: process,
                    isPinned: monitor.pinnedProcessIDs.contains(process.pid),
                    togglePinned: { monitor.togglePinnedProcess(process) },
                    terminateProcess: { monitor.terminateProcess(pid: process.pid) }
                )
            }
        } trailingHeader: {
            ProcessNetworkSortMenu(monitor: monitor)
        }
    }
}

struct SpikeProcessListView: View {
    let processes: [SpikeProcessSnapshot]
    let status: SpikeProcessSampleStatus
    let title: String

    init(
        processes: [SpikeProcessSnapshot],
        status: SpikeProcessSampleStatus,
        title: String = L10n.spikeProcessesTitle
    ) {
        self.processes = processes
        self.status = status
        self.title = title
    }

    var body: some View {
        ProcessListPanel(
            title: title,
            header: L10n.spikeProcessesHeader,
            isSampling: status.isSampling,
            errorMessage: status.errorMessage,
            samplingText: L10n.spikeProcessesSampling,
            emptyText: emptyText,
            isEmpty: processes.isEmpty
        ) {
            ForEach(processes) { process in
                SpikeProcessRow(process: process)
            }
        }
    }

    private var emptyText: String {
        switch status {
        case .sampling:
            return L10n.spikeProcessesSampling
        case .unavailable:
            return L10n.spikeProcessesUnavailable
        case .ready, .failed:
            return L10n.popoverProcessNoActivity
        }
    }
}

private struct ProcessListPanel<Rows: View, TrailingHeader: View>: View {
    let title: String
    let header: String
    let isSampling: Bool
    let errorMessage: String?
    let samplingText: String
    let emptyText: String
    let isEmpty: Bool
    @ViewBuilder let rows: () -> Rows
    @ViewBuilder var trailingHeader: () -> TrailingHeader

    init(
        title: String,
        header: String,
        isSampling: Bool,
        errorMessage: String?,
        samplingText: String = L10n.popoverProcessSampling,
        emptyText: String = L10n.popoverProcessNoActivity,
        isEmpty: Bool,
        @ViewBuilder rows: @escaping () -> Rows,
        @ViewBuilder trailingHeader: @escaping () -> TrailingHeader
    ) {
        self.title = title
        self.header = header
        self.isSampling = isSampling
        self.errorMessage = errorMessage
        self.samplingText = samplingText
        self.emptyText = emptyText
        self.isEmpty = isEmpty
        self.rows = rows
        self.trailingHeader = trailingHeader
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Label(title, systemImage: "list.bullet.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(header)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                trailingHeader()
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isEmpty {
                HStack(spacing: 6) {
                    if isSampling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSampling ? samplingText : emptyText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(height: 18)
            } else {
                rows()
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        }
        .accessibilityElement(children: .contain)
    }
}

private extension ProcessListPanel where TrailingHeader == EmptyView {
    init(
        title: String,
        header: String,
        isSampling: Bool,
        errorMessage: String?,
        samplingText: String = L10n.popoverProcessSampling,
        emptyText: String = L10n.popoverProcessNoActivity,
        isEmpty: Bool,
        @ViewBuilder rows: @escaping () -> Rows
    ) {
        self.init(
            title: title,
            header: header,
            isSampling: isSampling,
            errorMessage: errorMessage,
            samplingText: samplingText,
            emptyText: emptyText,
            isEmpty: isEmpty,
            rows: rows,
            trailingHeader: { EmptyView() }
        )
    }
}

private struct ProcessNetworkSortMenu: View {
    let monitor: ProcessNetworkMonitor

    var body: some View {
        Menu {
            ForEach(ProcessNetworkSortMode.allCases, id: \.self) { mode in
                Button {
                    monitor.sortMode = mode
                } label: {
                    Label(mode.displayName, systemImage: monitor.sortMode == mode ? "checkmark" : mode.systemImage)
                }
            }
        } label: {
            Label(monitor.sortMode.shortLabel, systemImage: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help(L10n.popoverNetworkSortHelp(monitor.sortMode.displayName))
        .accessibilityLabel(L10n.popoverNetworkSortHelp(monitor.sortMode.displayName))
    }
}

private struct ProcessResourceRow: View {
    let process: ProcessResourceUsage
    let kind: ProcessResourceKind
    let isPinned: Bool
    let togglePinned: () -> Void
    let terminateProcess: () -> Void

    var body: some View {
        ProcessUsageRow(
            pid: process.pid,
            name: process.name,
            valueText: valueText,
            accent: accent,
            fraction: fraction,
            accessibilityValue: accessibilityValue,
            isPinned: isPinned,
            togglePinned: togglePinned,
            terminateProcess: terminateProcess
        )
    }

    private var valueText: String {
        switch kind {
        case .cpu:
            return String(format: "%.1f%%", process.cpuPercent)
        case .memory:
            return "\(memoryFormatter.string(fromByteCount: process.memoryBytes)) \(String(format: "%.1f%%", process.memoryPercent))"
        }
    }

    private var fraction: Double {
        switch kind {
        case .cpu:
            return min(max(process.cpuPercent / 100, 0), 1)
        case .memory:
            return min(max(process.memoryPercent / 100, 0), 1)
        }
    }

    private var accent: Color {
        switch kind {
        case .cpu:
            return .blue
        case .memory:
            return .orange
        }
    }

    private var accessibilityValue: String {
        switch kind {
        case .cpu:
            return "\(L10n.popoverProcessCPUHeader) \(valueText)"
        case .memory:
            return "\(L10n.popoverProcessMemoryHeader) \(valueText)"
        }
    }

    private var memoryFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter
    }
}

private struct ProcessNetworkRow: View {
    let process: ProcessNetworkUsage
    let isPinned: Bool
    let togglePinned: () -> Void
    let terminateProcess: () -> Void

    var body: some View {
        ProcessUsageRow(
            pid: process.pid,
            name: process.name,
            valueText: "↓\(formatSpeed(process.downloadBytesPerSec))  ↑\(formatSpeed(process.uploadBytesPerSec))",
            accent: .purple,
            fraction: activityFraction,
            accessibilityValue: "\(L10n.popoverNetworkDownload) \(formatSpeed(process.downloadBytesPerSec)), \(L10n.popoverNetworkUpload) \(formatSpeed(process.uploadBytesPerSec))",
            isPinned: isPinned,
            togglePinned: togglePinned,
            terminateProcess: terminateProcess
        )
    }

    private var activityFraction: Double {
        let total = Double(process.downloadBytesPerSec + process.uploadBytesPerSec)
        guard total > 0 else { return 0 }
        return min(log10(total + 1) / 7, 1)
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        MetricDisplayItem.formatSpeed(Double(bytesPerSecond)).trimmingCharacters(in: .whitespaces) + "/s"
    }
}

private struct SpikeProcessRow: View {
    let process: SpikeProcessSnapshot

    var body: some View {
        ProcessUsageRow(
            pid: process.pid,
            name: process.name,
            valueText: process.valueText,
            accent: accent,
            fraction: process.fraction,
            accessibilityValue: process.valueText,
            isPinned: false,
            togglePinned: nil,
            terminateProcess: nil
        )
    }

    private var accent: Color {
        switch process.metric {
        case .cpu:
            return .blue
        case .memory:
            return .orange
        case .network:
            return .purple
        }
    }
}

private struct ProcessUsageRow: View {
    let pid: Int
    let name: String
    let valueText: String
    let accent: Color
    let fraction: Double
    let accessibilityValue: String
    let isPinned: Bool
    let togglePinned: (() -> Void)?
    let terminateProcess: (() -> Void)?

    var body: some View {
        rowContent
            .modifier(ProcessPinInteraction(isPinned: isPinned, togglePinned: togglePinned))
            .modifier(ProcessRowContextMenu(
                copyPID: copyPID,
                terminateProcess: terminateProcess
            ))
            .frame(height: 24)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isPinned ? accent.opacity(0.14) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isPinned ? accent.opacity(0.28) : .clear, lineWidth: 1)
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ProcessIcon(pid: pid)

            HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProcessIDText(pid: pid)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(valueText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 72, alignment: .trailing)

                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(accent.opacity(0.65))
                                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        }
                }
                .frame(width: 72, height: 3)
            }
        }
    }

    private var accessibilityLabel: String {
        let pinText = isPinned ? "\(L10n.popoverProcessPinned), " : ""
        return "\(pinText)\(name), PID \(pid), \(accessibilityValue)"
    }

    private func copyPID() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(String(pid), forType: .string)
    }
}

private struct ProcessPinInteraction: ViewModifier {
    let isPinned: Bool
    let togglePinned: (() -> Void)?

    func body(content: Content) -> some View {
        if let togglePinned {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    togglePinned()
                }
                .help(isPinned ? L10n.popoverProcessUnpin : L10n.popoverProcessPin)
        } else {
            content
        }
    }
}

private struct ProcessRowContextMenu: ViewModifier {
    let copyPID: (() -> Void)?
    let terminateProcess: (() -> Void)?

    func body(content: Content) -> some View {
        if copyPID != nil || terminateProcess != nil {
            content.contextMenu {
                if let copyPID {
                    Button {
                        copyPID()
                    } label: {
                        Label(L10n.popoverProcessCopyPID, systemImage: "doc.on.doc")
                    }
                }

                if copyPID != nil, terminateProcess != nil {
                    Divider()
                }

                if let terminateProcess {
                    Button(role: .destructive) {
                        terminateProcess()
                    } label: {
                        Label(L10n.popoverProcessTerminate, systemImage: "xmark.circle")
                    }
                }
            }
            .accessibilityHint(L10n.popoverProcessContextMenuHint)
        } else {
            content
        }
    }
}

private struct ProcessIDText: View {
    let pid: Int

    var body: some View {
        Text("\(pid)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .help(L10n.popoverProcessContextMenuHint)
            .accessibilityLabel("PID \(pid)")
            .accessibilityHint(L10n.popoverProcessContextMenuHint)
    }
}

private struct ProcessIcon: View {
    let pid: Int

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 16, height: 16)
            .clipShape(.rect(cornerRadius: 3))
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)), let appIcon = app.icon {
            return appIcon
        }
        return NSWorkspace.shared.icon(forFile: "/bin/bash")
    }
}

private extension ProcessNetworkSortMode {
    var displayName: String {
        switch self {
        case .activity: return L10n.popoverNetworkSortActivity
        case .download: return L10n.popoverNetworkSortDownload
        case .upload: return L10n.popoverNetworkSortUpload
        case .total: return L10n.popoverNetworkSortTotal
        }
    }

    var shortLabel: String {
        switch self {
        case .activity: return L10n.popoverNetworkSortActivityShort
        case .download: return L10n.popoverNetworkSortDownloadShort
        case .upload: return L10n.popoverNetworkSortUploadShort
        case .total: return L10n.popoverNetworkSortTotalShort
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "bolt"
        case .download: return "arrow.down"
        case .upload: return "arrow.up"
        case .total: return "sum"
        }
    }
}

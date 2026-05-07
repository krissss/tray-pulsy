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
                ProcessResourceRow(process: process, kind: kind)
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
                ProcessNetworkRow(process: process)
            }
        } trailingHeader: {
            ProcessNetworkSortMenu(monitor: monitor)
        }
    }
}

private struct ProcessListPanel<Rows: View, TrailingHeader: View>: View {
    let title: String
    let header: String
    let isSampling: Bool
    let errorMessage: String?
    let isEmpty: Bool
    @ViewBuilder let rows: () -> Rows
    @ViewBuilder var trailingHeader: () -> TrailingHeader

    init(
        title: String,
        header: String,
        isSampling: Bool,
        errorMessage: String?,
        isEmpty: Bool,
        @ViewBuilder rows: @escaping () -> Rows,
        @ViewBuilder trailingHeader: @escaping () -> TrailingHeader
    ) {
        self.title = title
        self.header = header
        self.isSampling = isSampling
        self.errorMessage = errorMessage
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
                    Text(isSampling ? L10n.popoverProcessSampling : L10n.popoverProcessNoActivity)
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
        isEmpty: Bool,
        @ViewBuilder rows: @escaping () -> Rows
    ) {
        self.init(
            title: title,
            header: header,
            isSampling: isSampling,
            errorMessage: errorMessage,
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

    var body: some View {
        HStack(spacing: 8) {
            ProcessIcon(pid: process.pid)

            Text(process.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(valueText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: 20)
        .accessibilityLabel("\(process.name), \(accessibilityValue)")
    }

    private var valueText: String {
        switch kind {
        case .cpu:
            return String(format: "%.1f%%", process.cpuPercent)
        case .memory:
            return "\(memoryFormatter.string(fromByteCount: process.memoryBytes)) \(String(format: "%.1f%%", process.memoryPercent))"
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

    var body: some View {
        HStack(spacing: 8) {
            ProcessIcon(pid: process.pid)

            Text(process.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text("↓\(formatSpeed(process.downloadBytesPerSec))")
                Text("↑\(formatSpeed(process.uploadBytesPerSec))")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .frame(height: 20)
        .accessibilityLabel("\(process.name), \(L10n.popoverNetworkDownload) \(formatSpeed(process.downloadBytesPerSec)), \(L10n.popoverNetworkUpload) \(formatSpeed(process.uploadBytesPerSec))")
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        MetricDisplayItem.formatSpeed(Double(bytesPerSecond)).trimmingCharacters(in: .whitespaces) + "/s"
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

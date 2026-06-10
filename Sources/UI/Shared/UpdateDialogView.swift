import SwiftUI

struct UpdateDialogView: View {
    @Bindable var state: UpdateDialogState

    var body: some View {
        GlassEffectContainer {
            ZStack {
                background

                VStack(spacing: 0) {
                    header

                    Divider()
                        .opacity(0.55)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            statusContent
                            releaseNotesContent
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 260)

                    Divider()
                        .opacity(0.55)

                    footer
                }
            }
        }
        .frame(width: 560, height: 520)
    }

    private var accentColor: Color { .purple }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                stops: [
                    .init(color: accentColor.opacity(0.065), location: 0),
                    .init(color: accentColor.opacity(0.026), location: 0.32),
                    .init(color: .clear, location: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.20),
                            accentColor.opacity(0.08),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 13) {
            AppIconImage(size: 44)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.26), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                subtitleView
            }

            Spacer(minLength: 16)
        }
        .padding(20)
    }

    @ViewBuilder
    private var subtitleView: some View {
        if state.currentVersion.isEmpty || state.latestVersion.isEmpty {
            Text(AppConstants.appName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            SettingsValueBadge(text: subtitle, color: accentColor)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state.phase {
        case .checking:
            statusPanel(systemImage: "arrow.triangle.2.circlepath", color: .blue) {
                progressRow(title: L10n.updateDialogChecking, progress: nil)
            }
        case .updateFound:
            if let message = state.message {
                statusPanel(systemImage: "arrow.down.circle.fill", color: .blue) {
                    statusText(message)
                }
            }
        case let .downloading(progress):
            statusPanel(systemImage: "arrow.down.circle.fill", color: .blue) {
                progressRow(title: L10n.updateDialogDownloading, progress: progress)
            }
        case let .extracting(progress):
            statusPanel(systemImage: "shippingbox.fill", color: .orange) {
                progressRow(title: L10n.updateDialogExtracting, progress: progress)
            }
        case .readyToInstall:
            statusPanel(systemImage: "checkmark.seal.fill", color: .green) {
                statusText(L10n.updateDialogReadyMessage)
            }
        case .installing:
            statusPanel(systemImage: "arrow.triangle.2.circlepath.circle.fill", color: .blue) {
                progressRow(title: L10n.updateDialogInstalling, progress: nil)
            }
        case .installed:
            statusPanel(systemImage: "checkmark.circle.fill", color: .green) {
                statusText(L10n.updateDialogInstalledMessage)
            }
        case .notFound:
            statusPanel(systemImage: "checkmark.circle.fill", color: .green) {
                statusText(state.message ?? L10n.updateDialogNoUpdateMessage)
            }
        case .error:
            statusPanel(systemImage: "exclamationmark.triangle.fill", color: .red) {
                statusText(state.message ?? L10n.updateDialogErrorMessage, color: .red)
            }
        }
    }

    @ViewBuilder
    private var releaseNotesContent: some View {
        if !state.changelogEntries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader

                ForEach(state.changelogEntries) { entry in
                    changelogEntryPanel(entry)
                }
            }
        } else if let fallbackNotes = state.fallbackNotes, !fallbackNotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader

                SettingsInsetPanel(spacing: 8) {
                    UpdateMarkdownText(markdown: fallbackNotes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let skipAction = state.skipAction, showsSkipButton {
                Button {
                    skipAction()
                } label: {
                    Label(L10n.updateDialogSkip, systemImage: "forward.end.fill")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Spacer()

            if let cancelAction = state.cancelAction, showsCancelButton {
                Button {
                    cancelAction()
                } label: {
                    Label(L10n.updateDialogCancel, systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            if let dismissAction = state.dismissAction, showsLaterButton {
                Button {
                    dismissAction()
                } label: {
                    Label(L10n.updateDialogLater, systemImage: "clock.fill")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            if let acknowledgeAction = state.acknowledgeAction, state.isTerminal {
                Button {
                    acknowledgeAction()
                } label: {
                    Label(L10n.updateDialogOK, systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            if let installAction = state.installAction, showsInstallButton {
                Button {
                    installAction()
                } label: {
                    Label(installButtonTitle, systemImage: "arrow.down.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glass)
                .tint(.blue)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.secondary.opacity(0.035))
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            SettingsRowIcon(systemImage: "list.bullet.rectangle.fill", color: accentColor)

            Text(L10n.updateDialogChangesHeader)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }

    private func changelogEntryPanel(_ entry: UpdateChangelogEntry) -> some View {
        SettingsInsetPanel(spacing: 10) {
            HStack(spacing: 8) {
                Text(entry.displayTitle)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)
            }

            Divider()
                .opacity(0.45)

            UpdateMarkdownText(markdown: entry.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func statusPanel<Content: View>(
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsRowIcon(systemImage: systemImage, color: color)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.10), lineWidth: 1)
        }
    }

    private func statusText(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private func progressRow(title: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(.blue)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var title: String {
        switch state.phase {
        case .notFound:
            return L10n.updateDialogNoUpdateTitle
        case .error:
            return L10n.updateDialogErrorTitle
        case .readyToInstall:
            return L10n.updateDialogReadyTitle
        case .installing:
            return L10n.updateDialogInstalling
        case .installed:
            return L10n.updateDialogInstalledTitle
        default:
            if state.latestVersion.isEmpty {
                return L10n.updateDialogTitle
            }
            return String(format: L10n.updateDialogAvailableTitle, state.latestVersion)
        }
    }

    private var subtitle: String {
        if state.currentVersion.isEmpty || state.latestVersion.isEmpty {
            return AppConstants.appName
        }
        return String(format: L10n.updateDialogVersionRange, state.currentVersion, state.latestVersion)
    }

    private var showsInstallButton: Bool {
        switch state.phase {
        case .updateFound, .readyToInstall:
            true
        default:
            false
        }
    }

    private var showsLaterButton: Bool {
        switch state.phase {
        case .updateFound, .readyToInstall:
            true
        default:
            false
        }
    }

    private var showsSkipButton: Bool {
        if case .updateFound = state.phase { return true }
        return false
    }

    private var showsCancelButton: Bool {
        switch state.phase {
        case .checking, .downloading:
            true
        default:
            false
        }
    }

    private var installButtonTitle: String {
        if case .readyToInstall = state.phase {
            return L10n.updateDialogInstallAndRelaunch
        }
        return L10n.updateDialogInstall
    }
}

private struct UpdateMarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: MarkdownLine) -> some View {
        switch line {
        case let .heading(text):
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("-")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)

                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .text(text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)

        case .spacer:
            Spacer()
                .frame(height: 2)
        }
    }

    private var lines: [MarkdownLine] {
        var result: [MarkdownLine] = []
        var previousWasSpacer = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                if !previousWasSpacer {
                    result.append(.spacer)
                    previousWasSpacer = true
                }
                continue
            }

            previousWasSpacer = false

            if line.hasPrefix("### ") {
                result.append(.heading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("- ") {
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("* ") {
                result.append(.bullet(String(line.dropFirst(2))))
            } else {
                result.append(.text(line))
            }
        }

        while result.first == .spacer {
            result.removeFirst()
        }
        while result.last == .spacer {
            result.removeLast()
        }

        return result
    }

    private enum MarkdownLine: Equatable {
        case heading(String)
        case bullet(String)
        case text(String)
        case spacer
    }
}

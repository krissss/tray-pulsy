import SwiftUI

struct AboutDetail: View {
    @Environment(AppState.self) private var appState

    private var updateManager: AppUpdateManager { appState.updateManager }

    private var lastUpdateCheckString: String {
        if let date = updateManager.lastUpdateCheckDate {
            return date.formatted(date: .abbreviated, time: .standard)
        } else {
            return L10n.updateNeverChecked
        }
    }

    var body: some View {
        GlassEffectContainer {
            Form {
                // MARK: - App Identity
                Section {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .padding(8)
                            .glassEffect(in: .rect(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppConstants.appName)
                                .font(.title2.bold())
                            Text(String(format: L10n.aboutVersion, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Updates
                Section {
                    Toggle(L10n.updateAutoCheckToggle, isOn: Binding(
                        get: { updateManager.automaticallyChecksForUpdates },
                        set: { updateManager.automaticallyChecksForUpdates = $0; updateManager.updater.automaticallyChecksForUpdates = $0 }
                    ))

                    Toggle(L10n.updateAutoDownloadToggle, isOn: Binding(
                        get: { updateManager.automaticallyDownloadsUpdates },
                        set: { updateManager.automaticallyDownloadsUpdates = $0; updateManager.updater.automaticallyDownloadsUpdates = $0 }
                    ))

                    Picker(selection: Binding(
                        get: { UpdateCheckInterval.from(seconds: updateManager.updateCheckInterval) },
                        set: { updateManager.updateCheckInterval = $0.seconds; updateManager.updater.updateCheckInterval = $0.seconds }
                    )) {
                        ForEach(UpdateCheckInterval.allCases, id: \.rawValue) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    } label: {
                        Text(L10n.updateIntervalHeader)
                    }

                    HStack {
                        Button(L10n.updateCheckNow) {
                            updateManager.checkForUpdates()
                        }
                        .disabled(!updateManager.canCheckForUpdates)

                        Spacer()

                        Text(String(format: L10n.updateLastChecked, lastUpdateCheckString))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .opacity(updateManager.lastUpdateCheckDate == nil ? 0.75 : 1.0)
                    }
                } header: {
                    Text(L10n.updateAutoCheckHeader)
                }

                // MARK: - Info
                Section {
                    AboutLinkRow(icon: "person.fill", label: L10n.aboutDeveloper, value: "kriss", url: "https://github.com/krissss")
                    AboutLinkRow(icon: "chevron.left.forwardslash.chevron.right", label: "GITHUB", value: "GitHub", url: "https://github.com/krissss/tray-pulsy")
                    AboutLinkRow(icon: "lightbulb.fill", label: L10n.aboutInspiration, value: "RunCat365", url: "https://github.com/Kyome22/RunCat365")
                } header: {
                    Text(L10n.aboutInfoHeader)
                }

                // MARK: - Quit
                Section {
                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label(String(format: L10n.aboutQuit, AppConstants.appName), systemImage: "power")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct AboutLinkRow: View {
    let icon: String
    let label: String
    let value: String
    let url: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Link(value, destination: URL(string: url)!)
        }
    }
}

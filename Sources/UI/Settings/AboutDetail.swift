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
        SettingsFormPage {
            // MARK: - App Identity
            Section {
                HStack(spacing: 16) {
                    AppIconImage(size: 64)
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
                Toggle(isOn: Binding(
                    get: { updateManager.automaticallyChecksForUpdates },
                    set: { updateManager.automaticallyChecksForUpdates = $0; updateManager.updater.automaticallyChecksForUpdates = $0 }
                )) {
                    SettingsRowLabel(
                        title: L10n.updateAutoCheckToggle,
                        systemImage: "arrow.triangle.2.circlepath",
                        color: .blue
                    )
                }

                Toggle(isOn: Binding(
                    get: { updateManager.automaticallyDownloadsUpdates },
                    set: { updateManager.automaticallyDownloadsUpdates = $0; updateManager.updater.automaticallyDownloadsUpdates = $0 }
                )) {
                    SettingsRowLabel(
                        title: L10n.updateAutoDownloadToggle,
                        systemImage: "arrow.down.circle.fill",
                        color: .green
                    )
                }

                Picker(selection: Binding(
                    get: { UpdateCheckInterval.from(seconds: updateManager.updateCheckInterval) },
                    set: { updateManager.updateCheckInterval = $0.seconds; updateManager.updater.updateCheckInterval = $0.seconds }
                )) {
                    ForEach(UpdateCheckInterval.allCases, id: \.rawValue) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.updateIntervalHeader,
                        systemImage: "calendar.badge.clock",
                        color: .purple
                    )
                }

                HStack(spacing: 10) {
                    SettingsRowIcon(systemImage: "clock.badge.checkmark", color: .purple)
                    Text(String(format: L10n.updateLastChecked, lastUpdateCheckString))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .opacity(updateManager.lastUpdateCheckDate == nil ? 0.75 : 1.0)
                    Spacer(minLength: 12)
                    Button {
                        updateManager.checkForUpdates()
                    } label: {
                        Label(L10n.updateCheckNow, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(!updateManager.canCheckForUpdates)
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
    }
}

private struct AboutLinkRow: View {
    let icon: String
    let label: String
    let value: String
    let url: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowLabel(title: label, systemImage: icon, color: .purple)
            Spacer(minLength: 12)
            Link(value, destination: URL(string: url)!)
        }
    }
}

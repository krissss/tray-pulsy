import Defaults
import ServiceManagement
import SwiftUI

struct GeneralDetail: View {
    @Environment(AppState.self) private var appState
    @Default(.launchAtStartup) private var launchAtStartup
    @Default(.language) private var language

    private var updateManager: AppUpdateManager { appState.updateManager }

    var body: some View {
        GlassEffectContainer {
            Form {
                Section {
                    Toggle(isOn: $launchAtStartup) {
                        Label(L10n.generalStartupToggle, systemImage: "power.circle")
                    }
                    .onChange(of: launchAtStartup) {
                        toggleLaunchAtLogin(launchAtStartup)
                    }
                } header: {
                    Text(L10n.generalStartupHeader)
                } footer: {
                    Text(String(format: L10n.generalStartupFooter, AppConstants.appName))
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { updateManager.autoCheckEnabled },
                        set: { updateManager.setAutoCheck($0) }
                    )) {
                        Label(L10n.updateAutoCheckToggle, systemImage: "arrow.trianglehead.clockwise")
                    }

                    if updateManager.autoCheckEnabled {
                        Picker(selection: Binding(
                            get: { updateManager.currentInterval() },
                            set: { updateManager.setCheckInterval($0) }
                        )) {
                            ForEach(UpdateCheckInterval.allCases, id: \.rawValue) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        } label: {
                            Label(L10n.updateIntervalHeader, systemImage: "clock.arrow.circlepath")
                        }
                    }

                    updateStatusView
                } header: {
                    HStack {
                        Text(L10n.updateAutoCheckHeader)
                        Spacer()
                        Button {
                            updateManager.checkForUpdates()
                        } label: {
                            HStack(spacing: 4) {
                                if updateManager.checkState == .checking {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(updateManager.checkState == .checking ? L10n.updateChecking : L10n.updateCheckNow)
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(updateManager.checkState == .checking)
                    }
                }

                Section {
                    Picker(selection: $language) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    } label: {
                        Label(L10n.generalLanguageHeader, systemImage: "globe")
                    }
                } header: {
                    Text(L10n.generalLanguageHeader)
                }
                .onChange(of: language) {
                    language.apply()
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Update Status

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.checkState {
        case .upToDate:
            Label(L10n.updateUpToDate, systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .available(let version):
            VStack(alignment: .leading, spacing: 6) {
                Label(String(format: L10n.updateNewVersion, version), systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let notes = updateManager.releaseNotes, !notes.isEmpty {
                    DisclosureGroup {
                        Text((try? AttributedString(markdown: notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(notes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: {
                        Text(L10n.updateReleaseNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = URL(string: "https://github.com/krissss/tray-pulsy/releases/latest") {
                    Link(destination: url) {
                        Label(L10n.updateViewDetails, systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
        case .error(let message):
            Label(String(format: L10n.updateError, message), systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.red)
        case .idle, .checking:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("⚠️ Launch-at-login error: \(error)")
        }
    }
}

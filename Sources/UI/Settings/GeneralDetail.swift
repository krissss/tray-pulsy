import Defaults
import ServiceManagement
import SwiftUI

struct GeneralDetail: View {
    @Default(.launchAtStartup) private var launchAtStartup
    @Default(.keepAwakeEnabled) private var keepAwakeEnabled
    @Default(.keepAwakeDuration) private var keepAwakeDuration
    @Default(.language) private var language

    var body: some View {
        SettingsFormPage {
            Section {
                Toggle(isOn: $launchAtStartup) {
                    SettingsRowLabel(
                        title: L10n.generalStartupToggle,
                        systemImage: "power.circle.fill",
                        color: .green
                    )
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
                Toggle(isOn: $keepAwakeEnabled) {
                    SettingsRowLabel(
                        title: L10n.generalKeepAwakeToggle,
                        systemImage: "moon.zzz.fill",
                        color: .orange
                    )
                }

                Picker(selection: $keepAwakeDuration) {
                    ForEach(KeepAwakeDuration.allCases, id: \.rawValue) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.generalKeepAwakeDuration,
                        systemImage: "timer",
                        color: .orange
                    )
                }
                .disabled(!keepAwakeEnabled)
            } header: {
                Text(L10n.generalKeepAwakeHeader)
            } footer: {
                Text(L10n.generalKeepAwakeFooter)
            }

            Section {
                Picker(selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.generalLanguageHeader,
                        systemImage: "globe",
                        color: .blue
                    )
                }
            } header: {
                Text(L10n.generalLanguageHeader)
            }
            .onChange(of: language) {
                language.apply()
            }
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

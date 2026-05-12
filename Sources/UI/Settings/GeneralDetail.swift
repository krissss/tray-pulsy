import Defaults
import ServiceManagement
import SwiftUI

struct GeneralDetail: View {
    @Default(.launchAtStartup) private var launchAtStartup
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

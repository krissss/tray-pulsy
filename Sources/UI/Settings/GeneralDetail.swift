import SwiftUI
import Defaults
import ServiceManagement

struct GeneralDetail: View {
    @Default(.launchAtStartup) private var launchAtStartup
    @Default(.language) private var language

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

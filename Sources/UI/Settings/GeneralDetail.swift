import SwiftUI
import Defaults
import ServiceManagement

struct GeneralDetail: View {
    @Default(.launchAtStartup) private var launchAtStartup

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtStartup) {
                    Label("开机自动启动", systemImage: "power.circle")
                }
                .onChange(of: launchAtStartup) {
                    toggleLaunchAtLogin(launchAtStartup)
                }
            } header: {
                Text("启动")
            } footer: {
                Text("登录时自动在菜单栏启动 \(AppConstants.appName)。")
            }
        }
        .formStyle(.grouped)
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

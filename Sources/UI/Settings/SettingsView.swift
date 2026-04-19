import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("概览", systemImage: "chart.bar.fill", value: SettingsSection.overview) {
                OverviewDetail()
            }
            Tab("外观", systemImage: "paintpalette.fill", value: SettingsSection.appearance) {
                AppearanceDetail()
            }
            Tab("性能", systemImage: "gauge.with.dots.needle.33percent", value: SettingsSection.performance) {
                PerformanceDetail()
            }
            Tab("通用", systemImage: "gearshape.fill", value: SettingsSection.general) {
                GeneralDetail()
            }
            Tab("关于", systemImage: "info.circle.fill", value: SettingsSection.about) {
                AboutDetail()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("概览", systemImage: "chart.bar.fill", value: SettingsSection.overview) {
                OverviewDetail().navigationTitle(selectedTab.title)
            }
            Tab("皮肤", systemImage: "paintpalette.fill", value: SettingsSection.skin) {
                SkinDetail().navigationTitle(selectedTab.title)
            }
            Tab("指标", systemImage: "chart.bar.doc.horizontal", value: SettingsSection.metrics) {
                MetricsDetail().navigationTitle(selectedTab.title)
            }
            Tab("性能", systemImage: "gauge.with.dots.needle.33percent", value: SettingsSection.performance) {
                PerformanceDetail().navigationTitle(selectedTab.title)
            }
            Tab("通用", systemImage: "gearshape.fill", value: SettingsSection.general) {
                GeneralDetail().navigationTitle(selectedTab.title)
            }
            Tab("关于", systemImage: "info.circle.fill", value: SettingsSection.about) {
                AboutDetail().navigationTitle(selectedTab.title)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

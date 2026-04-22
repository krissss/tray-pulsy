import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("概览", systemImage: "chart.bar.fill", value: SettingsSection.overview) {
                OverviewDetail()
            }
            Tab("皮肤", systemImage: "paintpalette.fill", value: SettingsSection.skin) {
                SkinDetail()
            }
            Tab("指标", systemImage: "chart.bar.doc.horizontal", value: SettingsSection.metrics) {
                MetricsDetail()
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

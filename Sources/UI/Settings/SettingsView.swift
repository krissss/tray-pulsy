import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview
    /// Bumped on language change to force a full re-render with updated L10n strings.
    @State private var languageVersion = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(L10n.tabOverview, systemImage: "chart.bar.fill", value: SettingsSection.overview) {
                OverviewDetail().navigationTitle(selectedTab.title)
            }
            Tab(L10n.tabSkin, systemImage: "paintpalette.fill", value: SettingsSection.skin) {
                SkinDetail().navigationTitle(selectedTab.title)
            }
            Tab(L10n.tabMetrics, systemImage: "chart.bar.doc.horizontal", value: SettingsSection.metrics) {
                MetricsDetail().navigationTitle(selectedTab.title)
            }
            Tab(L10n.tabPerformance, systemImage: "gauge.with.dots.needle.33percent", value: SettingsSection.performance) {
                PerformanceDetail().navigationTitle(selectedTab.title)
            }
            Tab(L10n.tabGeneral, systemImage: "gearshape.fill", value: SettingsSection.general) {
                GeneralDetail().navigationTitle(selectedTab.title)
            }
            Tab(L10n.tabAbout, systemImage: "info.circle.fill", value: SettingsSection.about) {
                AboutDetail().navigationTitle(selectedTab.title)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .id(languageVersion)
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageVersion += 1
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview
    /// Bumped on language change to force a full re-render with updated L10n strings.
    @State private var languageVersion = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewDetail()
                .navigationTitle(selectedTab.title)
                .tabItem { Label(L10n.tabOverview, systemImage: "chart.bar.fill") }
                .tag(SettingsSection.overview)

            SkinDetail()
                .navigationTitle(selectedTab.title)
                .tabItem { Label(L10n.tabSkin, systemImage: "paintpalette.fill") }
                .tag(SettingsSection.skin)

            MetricsDetail()
                .navigationTitle(selectedTab.title)
                .tabItem { Label(L10n.tabMetrics, systemImage: "chart.bar.doc.horizontal") }
                .tag(SettingsSection.metrics)

            PerformanceDetail()
                .navigationTitle(selectedTab.title)
                .tabItem { Label(L10n.tabPerformance, systemImage: "gauge.with.dots.needle.33percent") }
                .tag(SettingsSection.performance)

            GeneralDetail()
                .navigationTitle(selectedTab.title)
                .tabItem { Label(L10n.tabGeneral, systemImage: "gearshape.fill") }
                .tag(SettingsSection.general)

            AboutDetail()
                .navigationTitle(selectedTab.title)
                .tabItem { Label(L10n.tabAbout, systemImage: "info.circle.fill") }
                .tag(SettingsSection.about)
        }
        .id(languageVersion)
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageVersion += 1
        }
    }
}

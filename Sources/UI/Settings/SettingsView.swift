import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview
    /// Bumped on language change to force a full re-render with updated L10n strings.
    @State private var languageVersion = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsSection.allCases) { section in
                Tab(value: section) {
                    section.contentView
                        .navigationTitle(section.title)
                } label: {
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(nsImage: section.coloredIcon)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .id(languageVersion)
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageVersion += 1
        }
    }
}

// MARK: - Section Content

private extension SettingsSection {
    @ViewBuilder
    var contentView: some View {
        switch self {
        case .overview:    OverviewDetail()
        case .skin:        SkinDetail()
        case .metrics:     MetricsDetail()
        case .performance: PerformanceDetail()
        case .general:     GeneralDetail()
        case .about:       AboutDetail()
        }
    }
}

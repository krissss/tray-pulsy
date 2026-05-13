import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsSection = .overview
    /// Bumped on language change to force a full re-render with updated L10n strings.
    @State private var languageVersion = 0

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selectedSection: $selectedTab)
                .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 224)
        } detail: {
            SettingsDetailPane(section: selectedTab) {
                selectedTab.contentView
            }
        }
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .id(languageVersion)
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageVersion += 1
        }
    }
}

// MARK: - Detail Pane

private struct SettingsDetailPane<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background {
                SettingsDetailBackground(color: section.color)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .navigationTitle(section.title)
    }
}

private struct SettingsDetailBackground: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                stops: [
                    .init(color: color.opacity(0.035), location: 0),
                    .init(color: color.opacity(0.016), location: 0.28),
                    .init(color: .clear, location: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.18),
                            color.opacity(0.08),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(spacing: 0) {
            SettingsSidebarHeader()

            Divider()
                .opacity(0.55)
                .padding(.horizontal, 12)

            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarItem(
                        section: section,
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.secondary.opacity(0.14))
                .frame(width: 1)
        }
    }
}

private struct SettingsSidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            AppIconImage(size: 34)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.26), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(AppConstants.appName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(L10n.windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }
}

private struct SettingsSidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(section.color)
                    .frame(width: 3, height: 18)
                    .opacity(isSelected ? 1 : 0)

                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : section.color)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(section.color.opacity(isSelected ? 0.92 : 0.13))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(section.color.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
                    }

                Text(section.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .padding(.vertical, 7)
            .contentShape(.rect(cornerRadius: 10, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(section.color.opacity(isSelected ? 0.20 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.14), value: isSelected)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var rowBackground: Color {
        if isSelected { return section.color.opacity(0.13) }
        if isHovering { return .secondary.opacity(0.08) }
        return .clear
    }
}

// MARK: - Section Content

private extension SettingsSection {
    @MainActor @ViewBuilder
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

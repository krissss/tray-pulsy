import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview    = "overview"
    case skin        = "skin"
    case metrics     = "metrics"
    case performance = "performance"
    case general     = "general"
    case about       = "about"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:    L10n.tabOverview
        case .skin:        L10n.tabSkin
        case .metrics:     L10n.tabMetrics
        case .performance: L10n.tabPerformance
        case .general:     L10n.tabGeneral
        case .about:       L10n.tabAbout
        }
    }

    var systemImage: String {
        switch self {
        case .overview:    "chart.bar.fill"
        case .skin:        "paintpalette.fill"
        case .metrics:     "chart.bar.doc.horizontal"
        case .performance: "gauge.with.dots.needle.33percent"
        case .general:     "gearshape.fill"
        case .about:       "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .overview:    .blue
        case .skin:        .pink
        case .metrics:     .orange
        case .performance: .green
        case .general:     .gray
        case .about:       .purple
        }
    }

}

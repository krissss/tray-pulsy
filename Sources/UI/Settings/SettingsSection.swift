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
}

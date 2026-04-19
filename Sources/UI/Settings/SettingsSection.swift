import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview    = "overview"
    case appearance  = "appearance"
    case performance = "performance"
    case general     = "general"
    case about       = "about"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:    "概览"
        case .appearance:  "外观"
        case .performance: "性能"
        case .general:     "通用"
        case .about:       "关于"
        }
    }

    var icon: String {
        switch self {
        case .overview:    "chart.bar.fill"
        case .appearance:  "paintpalette.fill"
        case .performance: "gauge.with.dots.needle.33percent"
        case .general:     "gearshape.fill"
        case .about:       "info.circle.fill"
        }
    }
}

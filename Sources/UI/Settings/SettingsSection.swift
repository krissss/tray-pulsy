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
        case .overview:    "概览"
        case .skin:        "皮肤"
        case .metrics:     "指标"
        case .performance: "性能"
        case .general:     "通用"
        case .about:       "关于"
        }
    }
}

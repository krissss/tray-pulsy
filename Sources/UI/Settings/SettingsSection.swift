import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview    = "overview"
    case skin        = "skin"
    case metrics     = "metrics"
    case performance = "performance"
    case general     = "general"
    case about       = "about"

    var id: String { rawValue }
}

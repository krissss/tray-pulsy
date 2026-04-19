import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview    = "overview"
    case appearance  = "appearance"
    case performance = "performance"
    case general     = "general"
    case about       = "about"

    var id: String { rawValue }
}

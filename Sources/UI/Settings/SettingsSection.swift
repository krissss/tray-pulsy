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

    /// Lazily-rendered colored icon cached per section.
    var coloredIcon: NSImage {
        IconCache.shared.icon(for: self)
    }
}

/// Pre-renders and caches colored tab icons on first access (main actor only).
private final class IconCache: @unchecked Sendable {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for section: SettingsSection) -> NSImage {
        if let cached = cache[section.rawValue] { return cached }
        let image = renderIcon(systemName: section.systemImage, color: section.color)
        cache[section.rawValue] = image
        return image
    }

    private func renderIcon(systemName: String, color: Color) -> NSImage {
        MainActor.assumeIsolated {
            let iconSize: CGFloat = 20
            let view = NSHostingView(rootView:
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color.gradient)
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: iconSize, height: iconSize)
            )
            let frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
            view.frame = frame
            view.layoutSubtreeIfNeeded()

            guard let rep = view.bitmapImageRepForCachingDisplay(in: frame) else {
                return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!
            }
            view.cacheDisplay(in: frame, to: rep)

            let image = NSImage(size: frame.size)
            image.addRepresentation(rep)
            return image
        }
    }
}

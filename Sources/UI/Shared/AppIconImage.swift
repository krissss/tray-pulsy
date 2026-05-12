import SwiftUI

struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static let icon: NSImage = {
        if let url = Bundle.module.url(
            forResource: "AppIcon",
            withExtension: "icns",
            subdirectory: "Resources"
        ),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSApp.applicationIconImage
    }()
}

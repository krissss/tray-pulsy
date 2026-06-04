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
        if let image = loadIconFromMainBundle() {
            return image
        }

        if let image = loadIconFromResourceBundle() {
            return image
        }

        return NSApp.applicationIconImage
    }()

    private static func loadIconFromMainBundle() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func loadIconFromResourceBundle() -> NSImage? {
        for bundleURL in resourceBundleURLs {
            guard let bundle = Bundle(url: bundleURL) else { continue }

            let iconURL = bundle.url(
                forResource: "AppIcon",
                withExtension: "icns",
                subdirectory: "Resources"
            ) ?? bundle.url(forResource: "AppIcon", withExtension: "icns")

            if let iconURL, let image = NSImage(contentsOf: iconURL) {
                return image
            }
        }

        return nil
    }

    private static var resourceBundleURLs: [URL] {
        [
            Bundle.main.bundleURL.appendingPathComponent("TrayPulsy_TrayPulsy.bundle"),
            Bundle.main.resourceURL?.appendingPathComponent("TrayPulsy_TrayPulsy.bundle")
        ].compactMap { $0 }
    }
}

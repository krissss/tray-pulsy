import AppKit

/// Programmatic sprite generator using SF Symbols.
/// Generates animated frames by applying per-frame transforms to Apple-designed symbols.
/// Result: crisp, Retina-quality icons at any scale — no external image dependencies.
enum SpriteGenerator {

    /// Generate animated frames from an SF Symbol with vertical bounce (running effect).
    /// - Parameters:
    ///   - symbolName: SF Symbol identifier (e.g. "cat.fill")
    ///   - frameCount: Number of animation frames (default: 5, matching original RunCat)
    ///   - size: Target size in points (default: 18pt for menu bar)
    ///   - symbolSize: Render size of the symbol itself (slightly smaller than canvas for breathing room)
    static func bouncingFrames(
        symbolName: String,
        frameCount: Int = 5,
        size: NSSize = NSSize(width: 18, height: 18),
        symbolSize: NSSize = NSSize(width: 17, height: 17)
    ) -> [NSImage] {
        guard let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            print("⚠️ RunCatX: SF Symbol '\(symbolName)' not available on this macOS version")
            return fallbackFrames(count: frameCount, size: size)
        }

        return (0..<frameCount).map { i in
            let phase = Double(i) / Double(frameCount)
            // Vertical bounce: sin wave creates natural running hop
            let yOffset = -sin(phase * .pi * 2) * 1.1

            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.clear.set()
            NSRect(origin: .zero, size: size).fill()

            NSColor.labelColor.set()
            let drawOrigin = NSPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2 + yOffset
            )
            baseSymbol.draw(
                in: NSRect(origin: drawOrigin, size: symbolSize),
                from: NSRect(origin: .zero, size: baseSymbol.size),
                operation: .copy,
                fraction: 1.0
            )

            image.unlockFocus()
            image.isTemplate = false
            return image
        }
    }

    // MARK: - Fallback

    private static func fallbackFrames(count: Int, size: NSSize) -> [NSImage] {
        (0..<count).map { _ in
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
            img.unlockFocus()
            img.isTemplate = false
            return img
        }
    }
}

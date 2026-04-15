import AppKit

/// Programmatic sprite generator using SF Symbols with vibrant colors.
/// Generates animated frames by extracting SF Symbol alpha mask + painting skin color.
/// Result: colorful, Retina-quality icons — no external image dependencies.
enum SpriteGenerator {

    // MARK: - Color Palette

    enum SkinColor {
        case cat; case dog; case frog; case snail; case bird

        var nsColor: NSColor {
            switch self {
            case .cat:   return NSColor(red: 1.00, green: 0.58, blue: 0.10, alpha: 1.0)  // 🟠 warm orange
            case .dog:   return NSColor(red: 0.65, green: 0.45, blue: 0.28, alpha: 1.0)  // 🤎 brown
            case .frog:  return NSColor(red: 0.35, green: 0.75, blue: 0.35, alpha: 1.0)  // 🟢 green
            case .snail: return NSColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1.0)  // 🔵 ocean blue
            case .bird:  return NSColor(red: 0.30, green: 0.65, blue: 0.90, alpha: 1.0)  // 🩵 sky blue
            }
        }

        /// Target RGBA components (8-bit sRGB).
        var rgba: (r: UInt8, g: UInt8, b: UInt8) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }
    }

    // MARK: - Frame Generation

    /// Generate animated frames from an SF Symbol with vertical bounce (running effect).
    /// Applies the skin's signature color via pixel-level alpha masking.
    static func bouncingFrames(
        symbolName: String,
        color: SkinColor = .cat,
        frameCount: Int = 5,
        size: NSSize = NSSize(width: 18, height: 18),
        symbolSize: NSSize = NSSize(width: 17, height: 17)
    ) -> [NSImage] {
        guard let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            print("⚠️ RunCatX: SF Symbol '\(symbolName)' not available on this macOS version")
            return []
        }

        // Pre-render symbol at canvas size to get alpha mask CGImage
        let maskImg = NSImage(size: size)
        maskImg.lockFocus()
        baseSymbol.draw(
            in: CGRect(x: (size.width - symbolSize.width) / 2, y: 0,
                       width: symbolSize.width, height: symbolSize.height),
            from: NSRect(origin: .zero, size: baseSymbol.size),
            operation: .copy, fraction: 1.0
        )
        maskImg.unlockFocus()
        guard let maskCG = maskImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        let w = maskCG.width, h = maskCG.height
        let maskProv = maskCG.dataProvider!
        let maskData = maskProv.data!
        let maskPtr = CFDataGetBytePtr(maskData)!
        let mbr = maskCG.bytesPerRow
        let comp = maskCG.bitsPerComponent / 8  // bytes per component (2 for 16-bit)

        let tgt = color.rgba

        return (0..<frameCount).map { i -> NSImage in
            let phase = Double(i) / Double(frameCount)
            let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
            let yOffsetPx = Int(-sin(phase * .pi * 2) * 1.1 * screenScale)

            // Output buffer: RGBA 8-bit premultiplied
            let outBR = w * 4
            var outBuf = [UInt8](repeating: 0, count: h * outBR)

            for row in 0..<h {
                let srcRow = row + yOffsetPx
                guard srcRow >= 0 && srcRow < h else { continue }
                for col in 0..<w {
                    let mOff = srcRow * mbr + col * (comp * 4)
                    let mOffEnd = mOff + comp * 4 - 1
                    guard mOffEnd < CFDataGetLength(maskData) else { continue }
                    // Read alpha from 16-bit mask (last component of RGBA)
                    let alpha16 = (UInt16(maskPtr[mOff + 6]) << 8) | UInt16(maskPtr[mOff + 7])
                    let a = UInt8(alpha16 >> 8)
                    guard a > 10 else { continue }

                    let o = row * outBR + col * 4
                    outBuf[o]     = UInt8((Int(tgt.r) * Int(a)) / 255)  // R premultiplied
                    outBuf[o + 1] = UInt8((Int(tgt.g) * Int(a)) / 255)  // G
                    outBuf[o + 2] = UInt8((Int(tgt.b) * Int(a)) / 255)  // B
                    outBuf[o + 3] = a                                    // A
                }
            }

            guard let ctx = CGContext(
                data: &outBuf, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: outBR,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cgOut = ctx.makeImage() else {
                return fallback(size: size, color: color)
            }

            let result = NSImage(cgImage: cgOut, size: size)
            result.isTemplate = false
            return result
        }
    }

    // MARK: - Fallback

    private static func fallback(size: NSSize, color: SkinColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        color.nsColor.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

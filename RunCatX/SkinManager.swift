import AppKit
import CoreImage

/// Manages skin (image frame sets) for the runner.
/// Supports Light/Dark theme-aware icon rendering with frame caching.
final class SkinManager: @unchecked Sendable {
    enum Skin: String, CaseIterable, Sendable {
        case cat; case horse; case parrot; case frog; case snail
        var label: String { rawValue }
        var emoji: String {
            switch self {
            case .cat:    return "🐱"
            case .horse:  return "🐴"
            case .parrot: return "🦜"
            case .frog:   return "🐸"
            case .snail:  return "🐌"
            }
        }
        /// SF Symbol name for settings preview thumbnails (non-PNG skins only).
        var iconName: String {
            switch self {
            case .cat:    return "fish.fill"       // not used — cat loads from PNG
            case .horse:  return "hare.fill"       // not used — horse loads from PNG
            case .parrot: return "bird.fill"       // not used — parrot loads from PNG
            case .frog:   return "leaf.fill"
            case .snail:  return "shell.fill"
            }
        }
    }

    static let shared = SkinManager()
    private(set) var currentSkin: Skin = .cat
    private var currentTheme: ThemeMode = .system

    /// Cache: (skin, themeHash) → themed frames.
    /// Avoids re-running CIFilter on every frames() call.
    private var frameCache: [String: [NSImage]] = [:]

    func setSkin(_ s: Skin) { currentSkin = s }
    func setTheme(_ t: ThemeMode) { currentTheme = t; clearCache() } // theme change → invalidate cache
    func nextSkin() -> Skin {
        let all = Skin.allCases
        guard let i = all.firstIndex(of: currentSkin) else { return .cat }
        currentSkin = all[(i + 1) % all.count]
        return currentSkin
    }

    /// Returns cached or freshly-themed frames for the given (or current) skin.
    func frames(for s: Skin? = nil) -> [NSImage] {
        let skin = s ?? currentSkin
        let cacheKey = cacheKeyFor(skin: skin)
        if let cached = frameCache[cacheKey] { return cached }

        let baseFrames = loadBaseFrames(for: skin)
        let themed = applyCurrentTheme(to: baseFrames)
        frameCache[cacheKey] = themed
        return themed
    }

    func frameCount() -> Int { frames().count }

    /// Single frame by index (for settings preview thumbnails).
    func frame(for skinName: String, frameIndex: Int) -> NSImage? {
        guard let s = Skin(rawValue: skinName) else { return nil }
        let all = frames(for: s)
        guard frameIndex >= 0 && frameIndex < all.count else { return nil }
        return all[frameIndex]
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Caching
    // ═════════════════════════════════════════════════════════

    private func cacheKeyFor(skin: Skin) -> String {
        "\(skin.rawValue):\(themeHash)"
    }

    private var themeHash: String {
        switch currentTheme {
        case .system: return "sys"
        case .dark:  return "dark"
        case .light: return "light"
        }
    }

    private func clearCache() { frameCache.removeAll() }

    // ═════════════════════════════════════════════════════════
    // MARK: - Base Frame Loading (no theme applied)
    // ═════════════════════════════════════════════════════════

    /// Loads unthemed base frames for a skin.
    private func loadBaseFrames(for skin: Skin) -> [NSImage] {
        switch skin {
        case .cat:    return CatRenderer.originalNSFrames
        case .horse:  return HorseRenderer.originalNSFrames
        case .parrot: return ParrotRenderer.originalNSFrames
        case .frog:   return FrogRenderer.nsFrames
        case .snail:  return SnailRenderer.nsFrames
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme Application (Light/Dark icon recoloring)
    // ═════════════════════════════════════════════════════════

    /// Applies theme-aware recoloring to frames.
    /// Dark mode: inverts luminance so dark icons show on light status bar.
    /// Light mode / System: returns original (no processing).
    private func applyCurrentTheme(to images: [NSImage]) -> [NSImage] {
        let isDark: Bool
        switch currentTheme {
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .dark:  isDark = true
        case .light: isDark = false
        }
        guard isDark else { return images }
        return images.map { recolorForDarkMode($0) }
    }

    /// Recolors an image for dark mode appearance.
    /// Mirrors Windows version's BitmapExtension.Recolor: preserve alpha, replace RGB.
    private func recolorForDarkMode(_ image: NSImage) -> NSImage {
        guard let cgImg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let ciImage = CIImage(cgImage: cgImg)

        // Invert brightness + boost contrast → dark cat becomes light-colored
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(-1.0, forKey: kCIInputBrightnessKey)
        filter.setValue(1.2, forKey: kCIInputContrastKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage,
              let cgOutput = createCGImage(from: output, size: CGSize(width: cgImg.width, height: cgImg.height)) else {
            return image
        }

        let result = NSImage(cgImage: cgOutput, size: image.size)
        result.isTemplate = false
        return result
    }

    private func createCGImage(from ciImage: CIImage, size: CGSize) -> CGImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let rect = CGRect(origin: .zero, size: size)
        return context.createCGImage(ciImage, from: rect)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Image Factory
// ═══════════════════════════════════════════════════════════════

private enum ImgFactory {
    private static let scale = NSScreen.main?.backingScaleFactor ?? 2.0

    static func draw(size: CGFloat = 18, _ body: (CGContext) -> Void) -> NSImage {
        guard let cg = drawCG(size: size, body) else { return fallback(size: size) }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    static func drawCG(size: CGFloat = 18, _ body: (CGContext) -> Void) -> CGImage? {
        let px = Int(size * scale)
        guard let ctx = CGContext(data: nil, width: px, height: px,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.scaleBy(x: scale, y: scale)
        body(ctx)
        return ctx.makeImage()
    }

    private static func fallback(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus(); NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        img.unlockFocus(); img.isTemplate = false; return img
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - CGContext helpers
// ═══════════════════════════════════════════════════════════════

private extension CGContext {
    func fillStrokeEllipse(_ r: CGRect) {
        addPath(CGPath(ellipseIn: r, transform: nil)); fillPath()
        addPath(CGPath(ellipseIn: r, transform: nil)); strokePath()
    }
    func fillOval(_ r: CGRect) { addPath(CGPath(ellipseIn: r, transform: nil)); fillPath() }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Cat Renderer — Official RunCat PNG sprites (Kyome22)
// ═══════════════════════════════════════════════════════════════

/// Cat uses the original hand-drawn PNG sprites from Kyome22's menubar_runcat.
/// 5 frames, artist-quality pixel art.
/// Resources live in RunCatX_RunCatX.bundle/cat/ (SPM resource bundle).
private enum CatRenderer {
    static let originalNSFrames: [NSImage] = {
        let bundle = resourceBundle()
        return (0..<5).compactMap { i -> NSImage? in
            guard let url = bundle.url(forResource: "\(i)", withExtension: "png",
                                       subdirectory: "cat") else {
                print("⚠️ RunCatX: missing cat sprite \(i).png in \(bundle.bundlePath)")
                return nil
            }
            let img = NSImage(contentsOf: url)
            img?.size = NSSize(width: 18, height: 18)
            return img
        }
    }()

    /// Locate the SPM resource bundle (RunCatX_RunCatX.bundle next to executable).
    private static func resourceBundle() -> Bundle {
        // SPM puts resources in {targetName}_{targetName}.bundle alongside the executable
        if let rb = Bundle(path: Bundle.main.bundlePath + "/RunCatX_RunCatX.bundle") { return rb }
        // Fallback: try Bundle.main (works when running via `swift run`)
        return .main
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Horse Renderer — Official RunCat365 PNG sprites
// ═══════════════════════════════════════════════════════════════

/// Horse uses the PNG sprites from RunCat365 (Windows version).
/// 5 frames, black silhouette style.
private enum HorseRenderer {
    static let originalNSFrames: [NSImage] = {
        let bundle = resourceBundle()
        return (0..<5).compactMap { i -> NSImage? in
            guard let url = bundle.url(forResource: "\(i)", withExtension: "png",
                                       subdirectory: "horse") else {
                print("⚠️ RunCatX: missing horse sprite \(i).png")
                return nil
            }
            let img = NSImage(contentsOf: url)
            img?.size = NSSize(width: 18, height: 18)
            return img
        }
    }()

    private static func resourceBundle() -> Bundle {
        if let rb = Bundle(path: Bundle.main.bundlePath + "/RunCatX_RunCatX.bundle") { return rb }
        return .main
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Frog Renderer — 16 frames programmatic
// ═══════════════════════════════════════════════════════════════

private enum FrogRenderer {
    static let nsFrames: [NSImage] = {
        let imgs = (0..<16).compactMap { drawFrame($0) }
        return imgs.isEmpty ? [fallback()] : imgs
    }()

    private static let f = CGColor(red: 0.50, green: 0.80, blue: 0.45, alpha: 1)
    private static let b = CGColor(red: 0.85, green: 0.92, blue: 0.80, alpha: 1)
    private static let s = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    private static let e = CGColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)

    private static func drawFrame(_ i: Int) -> NSImage? {
        ImgFactory.draw { c in
            c.setFillColor(f); c.setStrokeColor(s); c.setLineWidth(1.2); c.setLineCap(.round)
            let phase = Double(i) / 16.0 * .pi * 2
            let hop = max(0, sin(phase * 2)) * CGFloat(i) * 0.3
            let eOff = sin(phase) * 0.5

            c.fillStrokeEllipse(CGRect(x: 3, y: 5 + hop, width: 12, height: 8))
            c.setFillColor(b); c.fillOval(CGRect(x: 5.5, y: 6.5 + hop, width: 7, height: 5))
            c.setFillColor(f); c.setStrokeColor(s)
            ball(c, at: CGPoint(x: 6 + eOff, y: 12 + hop))
            ball(c, at: CGPoint(x: 11 - eOff, y: 12 + hop))
            c.setFillColor(e)
            c.fillOval(CGRect(x: 6.5 + eOff, y: 12.8 + hop, width: 1.2, height: 1.5))
            c.fillOval(CGRect(x: 11.5 - eOff, y: 12.8 + hop, width: 1.2, height: 1.5))
            let sp = CGFloat(i) * 0.18
            fLeg(c, x: 3, y: 6 + hop, a: -0.3 - sp)
            fLeg(c, x: 13, y: 6 + hop, a: 0.3 + sp)
            fLeg(c, x: 4, y: 5 + hop, a: -0.5 - sp)
            fLeg(c, x: 12, y: 5 + hop, a: 0.5 + sp)
        }
    }

    private static func ball(_ c: CGContext, at p: CGPoint) { c.fillStrokeEllipse(CGRect(x: p.x, y: p.y, width: 3.5, height: 4)) }
    private static func fLeg(_ c: CGContext, x: CGFloat, y: CGFloat, a: CGFloat) {
        c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: a)
        c.setStrokeColor(s); c.setLineWidth(1.2)
        c.move(to: .zero); c.addLine(to: CGPoint(x: -2, y: 3)); c.addLine(to: CGPoint(x: -3.5, y: 2.5))
        c.strokePath(); c.restoreGState()
    }
    private static func fallback() -> NSImage {
        ImgFactory.draw(size: 18) { c in
            c.setFillColor(f); c.fillOval(CGRect(x: 4, y: 4, width: 10, height: 10))
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Snail Renderer — 16 frames programmatic
// ═══════════════════════════════════════════════════════════════

private enum SnailRenderer {
    static let nsFrames: [NSImage] = {
        let imgs = (0..<16).compactMap { drawFrame($0) }
        return imgs.isEmpty ? [fallback()] : imgs
    }()

    private static let shell = CGColor(red: 0.75, green: 0.50, blue: 0.80, alpha: 1)
    private static let bodyC = CGColor(red: 0.90, green: 0.82, blue: 0.75, alpha: 1)
    private static let s = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    private static let e = CGColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)

    private static func drawFrame(_ i: Int) -> NSImage? {
        ImgFactory.draw { c in
            c.setLineWidth(1.2); c.setLineCap(.round); c.setLineJoin(.round)
            let phase = Double(i) / 16.0 * .pi * 2
            let creep = CGFloat(i) * 0.04
            let sx = 7 + creep, sy: CGFloat = 7

            c.setFillColor(shell); c.setStrokeColor(s)
            var j: CGFloat = 3
            while j >= 0.5 {
                c.fillOval(CGRect(x: sx - j, y: sy - j, width: j * 2, height: j * 2))
                c.addPath(CGPath(ellipseIn: CGRect(x: sx - j, y: sy - j, width: j * 2, height: j * 2), transform: nil))
                c.strokePath()
                j -= 0.5
            }

            c.setFillColor(bodyC); c.setStrokeColor(s)
            var fp = [CGPoint(x: sx + 1, y: sy + 2), CGPoint(x: sx + 5, y: sy + 1),
                     CGPoint(x: sx + 6, y: sy - 1), CGPoint(x: sx + 4, y: sy - 2),
                     CGPoint(x: sx, y: sy - 1), CGPoint(x: sx - 1, y: sy + 1)]
            var footP = CGMutablePath()
            footP.move(to: fp[0])
            for k in 1..<fp.count { footP.addLine(to: fp[k]) }
            c.addPath(footP); c.fillPath(); c.strokePath()

            stalk(c, base: CGPoint(x: sx + 4.5, y: sy + 1.5), a: -0.2 + sin(phase) * 0.1)
            stalk(c, base: CGPoint(x: sx + 5.5, y: sy + 1.5), a: 0.2 - sin(phase) * 0.1)

            if i > 3 {
                c.setStrokeColor(CGColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 0.4)); c.setLineWidth(0.8)
                for k in 0..<min(i / 3, 4) {
                    let ly = sy + 1 + CGFloat(k) * 1.5
                    c.move(to: CGPoint(x: sx - 2 - CGFloat(k) * 0.5, y: ly))
                    c.addLine(to: CGPoint(x: sx - 0.5 - CGFloat(k) * 0.3, y: ly))
                    c.strokePath()
                }
            }
        }
    }

    private static func stalk(_ c: CGContext, base: CGPoint, a: CGFloat) {
        c.saveGState(); c.translateBy(x: base.x, y: base.y); c.rotate(by: a)
        c.setStrokeColor(s); c.setLineWidth(0.8)
        c.move(to: .zero); c.addLine(to: CGPoint(x: 0, y: 2.5)); c.strokePath()
        c.setFillColor(e); c.fillOval(CGRect(x: -0.6, y: 2.5, width: 1.2, height: 1.2))
        c.restoreGState()
    }
    private static func fallback() -> NSImage {
        ImgFactory.draw(size: 18) { c in
            c.setFillColor(shell); c.fillOval(CGRect(x: 4, y: 4, width: 10, height: 10))
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Parrot Renderer — Official RunCat365 PNG sprites (10 frames!)
// ═══════════════════════════════════════════════════════════════

/// Parrot uses the PNG sprites from RunCat365 (Windows version).
/// 10 frames — smoothest animation of all skins!
private enum ParrotRenderer {
    static let originalNSFrames: [NSImage] = {
        let bundle = resourceBundle()
        return (0..<10).compactMap { i -> NSImage? in
            guard let url = bundle.url(forResource: "\(i)", withExtension: "png",
                                       subdirectory: "parrot") else {
                print("⚠️ RunCatX: missing parrot sprite \(i).png")
                return nil
            }
            let img = NSImage(contentsOf: url)
            img?.size = NSSize(width: 18, height: 18)
            return img
        }
    }()

    private static func resourceBundle() -> Bundle {
        if let rb = Bundle(path: Bundle.main.bundlePath + "/RunCatX_RunCatX.bundle") { return rb }
        return .main
    }
}

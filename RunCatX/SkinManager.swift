import AppKit
import CoreImage

/// Manages skin (image frame sets) for the runner.
/// Supports Light/Dark theme-aware icon rendering.
final class SkinManager: @unchecked Sendable {
    enum Skin: String, CaseIterable, Sendable {
        case cat; case dog; case frog; case snail; case bird
        var label: String { rawValue }
    }

    static let shared = SkinManager()
    private(set) var currentSkin: Skin = .cat
    private var currentTheme: ThemeMode = .system

    func setSkin(_ s: Skin) { currentSkin = s }
    func setTheme(_ t: ThemeMode) { currentTheme = t }
    func nextSkin() -> Skin {
        let all = Skin.allCases
        guard let i = all.firstIndex(of: currentSkin) else { return .cat }
        currentSkin = all[(i + 1) % all.count]
        return currentSkin
    }

    /// Returns frames themed for current mode.
    func frames(for s: Skin? = nil) -> [NSImage] {
        let skin = s ?? currentSkin
        let baseFrames: [NSImage]
        switch skin {
        case .cat:   baseFrames = CatRenderer.originalNSFrames
        case .dog:   baseFrames = DogRenderer.nsFrames
        case .frog:  baseFrames = FrogRenderer.nsFrames
        case .snail: return SnailRenderer.nsFrames  // no theme needed
        case .bird:  return BirdRenderer.nsFrames     // no theme needed
        }
        return applyTheme(to: baseFrames)
    }

    func frameCount() -> Int { frames().count }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme Application (Light/Dark icon recoloring)
    // ═════════════════════════════════════════════════════════

    /// Applies theme-aware recoloring to frames.
    /// Dark mode: inverts luminance so dark icons show on light status bar.
    /// Light mode / System: returns original.
    private func applyTheme(to images: [NSImage]) -> [NSImage] {
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

        // Invert luminance + boost contrast → dark cat becomes light-colored
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(-1.0, forKey: kCIInputBrightnessKey)   // invert brightness
        filter.setValue(1.2, forKey: kCIInputContrastKey)       // boost contrast
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

    /// Draw into NSImage (legacy compat)
    static func draw(size: CGFloat = 18, _ body: (CGContext) -> Void) -> NSImage {
        guard let cg = drawCG(size: size, body) else { return fallback(size: size) }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    /// Draw directly to CGImage — no NSImage wrapper overhead.
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
// MARK: - Cat Renderer — 16 frames (smooth run cycle)
// ═══════════════════════════════════════════════════════════════

private enum CatRenderer {
    /// Load original Kyome22 sprite PNGs (5 frames, 126×77 artist-drawn)
    static let originalNSFrames: [NSImage] = {
        (0..<5).compactMap { i -> NSImage? in
            guard let url = Bundle.module.url(forResource: "\(i)", withExtension: "png",
                                              subdirectory: "cat") else {
                print("⚠️ RunCatX: missing cat sprite \(i).png")
                return nil
            }
            let img = NSImage(contentsOf: url)
            img?.size = NSSize(width: 18, height: 18) // status bar size
            return img
        }
    }()
    private static let f = CGColor(red: 1.00, green: 0.76, blue: 0.48, alpha: 1) // orange
    private static let s = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1) // stroke
    private static let e = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1) // eye

    /// (headOffset, leftFront, rightFront, leftBack, rightBack, tailAngle, mouthLevel, bigEyes)
    private static let keyframes: [(CGPoint, Int, Int, Int, Int, CGFloat, Int, Bool)] = [
        (CGPoint(x: 0, y: 0),     0,   0,   0,   0,   0,    0, false),  // 0: idle
        (CGPoint(x: 0.5, y: 0.3), 0,   0,   0,   0,   0.08, 0, false),  // 1
        (CGPoint(x: 1, y: 0.5),   1,  -1,  -1,   1,   0.15, 0, false),  // 2: walk start
        (CGPoint(x: 1.5, y: 0.8), 1,  -1,  -1,   1,   0.22, 0, false),  // 3
        (CGPoint(x: 2, y: 1),     2,  -2,  -2,   2,   0.30, 1, false),  // 4: jog
        (CGPoint(x: 2.5, y: 1.3), 2,  -2,  -2,   2,   0.38, 1, false),  // 5
        (CGPoint(x: 3, y: 1.5),   3,  -3,  -3,   3,   0.45, 2, true ),  // 6: run
        (CGPoint(x: 3.3, y: 1.7), 3,  -3,  -3,   3,   0.52, 2, true ),  // 7
        (CGPoint(x: 3.5, y: 1.9), 3,  -3,  -3,   3,   0.58, 3, true ),  // 8: fast run
        (CGPoint(x: 3.8, y: 2.1), 3,  -3,  -3,   3,   0.64, 3, true ),  // 9
        (CGPoint(x: 4, y: 2.2),   4,  -4,  -4,   4,   0.70, 4, true ),  // 10: sprint
        (CGPoint(x: 4.2, y: 2.3), 4,  -4,  -4,   4,   0.76, 4, true ),  // 11
        (CGPoint(x: 4.4, y: 2.4), 4,  -4,  -4,   4,   0.82, 4, true ),  // 12: blazing
        (CGPoint(x: 4.5, y: 2.5), 4,  -4,  -4,   4,   0.88, 4, true ),  // 13
        (CGPoint(x: 4.6, y: 2.5), 4,  -4,  -4,   4,   0.94, 4, true ),  // 14
        (CGPoint(x: 4.7, y: 2.5), 4,  -4,  -4,   4,   1.0, 4, true ),  // 15: max
    ]

    private static func drawCGFrame(_ i: Int) -> CGImage? {
        ImgFactory.drawCG { c in
            if i == 0 { idle(c); return }
            let kf = keyframes[i]
            pose(c, hOff: kf.0, lF: kf.1, rF: kf.2, lB: kf.3, rB: kf.4, tA: kf.5, ml: kf.6, big: kf.7)
        }
    }

    // ── Poses ──

    private static func idle(_ c: CGContext) {
        c.fillStrokeEllipse(CGRect(x: 3, y: 4, width: 12, height: 9))     // body
        c.fillStrokeEllipse(CGRect(x: 11, y: 10, width: 7, height: 6))      // head
        ear(c, at: CGPoint(x: 12, y: 15.5), a: -0.3)
        ear(c, at: CGPoint(x: 16, y: 15.5), a: 0.3)
        // closed eyes
        c.setStrokeColor(e); c.setLineWidth(0.8)
        qCurve(c, f: CGPoint(x: 13, y: 12.5), cp: CGPoint(x: 14.25, y: 13), t: CGPoint(x: 15.5, y: 12.5))
        qCurve(c, f: CGPoint(x: 13, y: 11.5), cp: CGPoint(x: 14.25, y: 12), t: CGPoint(x: 15.5, y: 11.5))
        // zzz
        c.setFillColor(e)
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 5),
                                                     .foregroundColor: NSColor(cgColor: e)!]
        ("z" as NSString).draw(at: CGPoint(x: 17, y: 14), withAttributes: attr)
    }

    private static func pose(_ c: CGContext, hOff: CGPoint, lF: Int, rF: Int, lB: Int, rB: Int,
                             tA: CGFloat, ml: Int = 0, big: Bool = false) {
        bodyHead(c, offset: hOff)
        legs(c, lF: lF, rF: rF, lB: lB, rB: rB)
        tail(c, angle: tA)
        dotEyes(c, cx: 10 + hOff.x + 4, cy: 9 + hOff.y + 2.5, big: big)
        if ml > 0 { motionLines(c, n: ml) }
    }

    private static func blazing(_ c: CGContext) {
        c.fillStrokeEllipse(CGRect(x: 1, y: 6, width: 16, height: 6))
        c.fillStrokeEllipse(CGRect(x: 14, y: 9, width: 5, height: 5))
        ear(c, at: CGPoint(x: 14.5, y: 13.5), a: -0.4)
        ear(c, at: CGPoint(x: 17.5, y: 13.5), a: 0.4)
        c.setFillColor(e)
        c.fillOval(CGRect(x: 15.5, y: 11, width: 1.5, height: 1.5))
        c.fillOval(CGRect(x: 17, y: 11, width: 1.5, height: 1.5))
        motionLines(c, n: 8)
    }

    // ── Shared parts ──

    private static func bodyHead(_ c: CGContext, offset: CGPoint) {
        c.fillStrokeEllipse(CGRect(x: 3, y: 5, width: 11, height: 8))
        let hx = 10 + offset.x, hy = 9 + offset.y
        c.fillStrokeEllipse(CGRect(x: hx, y: hy, width: 6.5, height: 5.5))
        ear(c, at: CGPoint(x: hx + 0.5, y: hy + 5.2), a: -0.3)
        ear(c, at: CGPoint(x: hx + 4.5, y: hy + 5.2), a: 0.3)
    }

    private static func ear(_ c: CGContext, at p: CGPoint, a: CGFloat) {
        c.saveGState(); c.translateBy(x: p.x, y: p.y); c.rotate(by: a)
        var path = CGMutablePath()
        path.move(to: CGPoint(x: -1.5, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 3.5))
        path.addLine(to: CGPoint(x: 1.5, y: 0))
        c.addPath(path); c.fillPath(); c.strokePath()
        c.restoreGState()
    }

    private static func dotEyes(_ c: CGContext, cx: CGFloat, cy: CGFloat, big: Bool = false) {
        c.setFillColor(e)
        let sz: CGFloat = big ? 1.8 : 1.4
        c.fillOval(CGRect(x: cx, y: cy, width: sz, height: sz))
        c.fillOval(CGRect(x: cx + 2, y: cy, width: sz, height: sz))
    }

    private static func legs(_ c: CGContext, lF: Int, rF: Int, lB: Int, rB: Int) {
        c.setStrokeColor(s); c.setLineWidth(1.5)
        let baseY: CGFloat = 5
        leg(c, x: 6, y: baseY, o: lF); leg(c, x: 8.5, y: baseY, o: rF)
        leg(c, x: 8, y: baseY, o: lB); leg(c, x: 10.5, y: baseY, o: rB)
    }

    private static func leg(_ c: CGContext, x: CGFloat, y: CGFloat, o: Int) {
        let lift = CGFloat(o) * 0.8, fwd = CGFloat(abs(o)) * 0.6
        let d: CGFloat = o >= 0 ? 1 : -1
        c.move(to: CGPoint(x: x, y: y))
        c.addQuadCurve(to: CGPoint(x: x + fwd * d, y: y - lift - 2),
                       control: CGPoint(x: x + fwd * 0.5 * d, y: y - lift * 0.5))
        c.strokePath()
    }

    private static func tail(_ c: CGContext, angle: CGFloat) {
        c.setStrokeColor(s); c.setLineWidth(1.3)
        c.saveGState(); c.translateBy(x: 3, y: 9); c.rotate(by: angle)
        c.move(to: .zero)
        c.addQuadCurve(to: CGPoint(x: -3, y: 4), control: CGPoint(x: -2, y: 2))
        c.addQuadCurve(to: CGPoint(x: -1, y: 6), control: CGPoint(x: -3, y: 5.5))
        c.strokePath(); c.restoreGState()
    }

    private static func motionLines(_ c: CGContext, n: Int) {
        c.setStrokeColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.5))
        c.setLineWidth(0.6)
        for i in 0..<n {
            let y = 4 + CGFloat(i) * 2
            c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: 2.5, y: y)); c.strokePath()
        }
    }

    private static func qCurve(_ c: CGContext, f: CGPoint, cp: CGPoint, t: CGPoint) {
        var p = CGMutablePath()
        p.move(to: f)
        p.addQuadCurve(to: t, control: cp)
        c.addPath(p); c.strokePath()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Dog Renderer
// ═══════════════════════════════════════════════════════════════

private enum DogRenderer {
    static let cgFrames: [CGImage] = (0..<16).compactMap { drawCGFrame($0) }
    static let nsFrames: [NSImage] = cgFrames.map { NSImage(cgImage: $0, size: NSSize(width: 18, height: 18)) }
    private static let f = CGColor(red: 0.85, green: 0.70, blue: 0.50, alpha: 1)
    private static let s = CGColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1)
    private static let n = CGColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1)
    private static let tongue = CGColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1)

    private static func drawCGFrame(_ i: Int) -> CGImage? {
        ImgFactory.drawCG { c in
            c.setFillColor(f); c.setStrokeColor(s); c.setLineWidth(1.2); c.setLineCap(.round)
            let phase = Double(i) / 16.0 * .pi * 2
            let bounce = abs(sin(phase * 2)) * 1.0
            let wobble = sin(phase * 3) * 0.3
            let hx = 10 + CGFloat(i) * 0.25, hy = 9 + bounce

            c.fillStrokeEllipse(CGRect(x: 3, y: 5 + bounce, width: 11, height: 7))
            c.fillStrokeEllipse(CGRect(x: hx, y: hy, width: 6.5, height: 6))
            for (dx, da) in [(CGFloat(0.5), -0.5 + wobble), (CGFloat(4.5), 0.5 - wobble)] {
                c.saveGState(); c.translateBy(x: hx + dx, y: hy + 5); c.rotate(by: da)
                c.fillStrokeEllipse(CGRect(x: -1.5, y: 0, width: 3, height: 4))
                c.restoreGState()
            }
            c.setFillColor(n)
            c.fillOval(CGRect(x: hx + 2.5, y: hy + 1.5, width: 1.5, height: 1.2))
            if i > 8 { c.setFillColor(tongue); c.fillOval(CGRect(x: hx + 2.7, y: hy - 0.3, width: 1.1, height: 1.8)) }
            c.setFillColor(n)
            c.fillOval(CGRect(x: hx + 1.2, y: hy + 3.5, width: 1.3, height: 1.5))
            c.fillOval(CGRect(x: hx + 3.5, y: hy + 3.5, width: 1.3, height: 1.5))
            c.setStrokeColor(s); c.setLineWidth(1.3)
            c.saveGState(); c.translateBy(x: 3, y: 8 + bounce); c.rotate(by: sin(phase * 4) * 0.6)
            c.move(to: .zero)
            c.addCurve(to: CGPoint(x: -2, y: 4), control1: CGPoint(x: -1.5, y: 1), control2: CGPoint(x: -2.5, y: 3))
            c.strokePath(); c.restoreGState()
            if i > 5 {
                c.setStrokeColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.5)); c.setLineWidth(0.6)
                for j in 0..<min(i - 3, 6) {
                    let ly = 4 + CGFloat(j) * 2
                    c.move(to: CGPoint(x: 0, y: ly)); c.addLine(to: CGPoint(x: 2, y: ly)); c.strokePath()
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Frog Renderer
// ═══════════════════════════════════════════════════════════════

private enum FrogRenderer {
    static let cgFrames: [CGImage] = (0..<16).compactMap { drawCGFrame($0) }
    static let nsFrames: [NSImage] = cgFrames.map { NSImage(cgImage: $0, size: NSSize(width: 18, height: 18)) }
    private static let f = CGColor(red: 0.50, green: 0.80, blue: 0.45, alpha: 1)
    private static let b = CGColor(red: 0.85, green: 0.92, blue: 0.80, alpha: 1)
    private static let s = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    private static let e = CGColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)

    private static func drawCGFrame(_ i: Int) -> CGImage? {
        ImgFactory.drawCG { c in
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
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Snail Renderer
// ═══════════════════════════════════════════════════════════════

private enum SnailRenderer {
    static let cgFrames: [CGImage] = (0..<16).compactMap { drawCGFrame($0) }
    static let nsFrames: [NSImage] = cgFrames.map { NSImage(cgImage: $0, size: NSSize(width: 18, height: 18)) }
    private static let shell = CGColor(red: 0.75, green: 0.50, blue: 0.80, alpha: 1)
    private static let body = CGColor(red: 0.90, green: 0.82, blue: 0.75, alpha: 1)
    private static let s = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    private static let e = CGColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)

    private static func drawCGFrame(_ i: Int) -> CGImage? {
        ImgFactory.drawCG { c in
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

            c.setFillColor(body); c.setStrokeColor(s)
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
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Bird Renderer
// ═══════════════════════════════════════════════════════════════

private enum BirdRenderer {
    static let cgFrames: [CGImage] = (0..<16).compactMap { drawCGFrame($0) }
    static let nsFrames: [NSImage] = cgFrames.map { NSImage(cgImage: $0, size: NSSize(width: 18, height: 18)) }
    private static let bC = CGColor(red: 0.30, green: 0.60, blue: 0.95, alpha: 1)
    private static let bellyC = CGColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1)
    private static let beakC = CGColor(red: 1.00, green: 0.75, blue: 0.20, alpha: 1)
    private static let s = CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    private static let e = CGColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)

    private static func drawCGFrame(_ i: Int) -> CGImage? {
        ImgFactory.drawCG { c in
            c.setLineWidth(1.2); c.setLineCap(.round); c.setLineJoin(.round)
            let phase = Double(i) / 16.0 * .pi * 2
            let flap = sin(phase * 2) * (2.0 + CGFloat(i) * 0.15)
            let hover = abs(sin(phase)) * (1.5 + CGFloat(i) * 0.08)

            c.setFillColor(bC); c.setStrokeColor(s)
            c.fillStrokeEllipse(CGRect(x: 4, y: 5 + hover, width: 10, height: 7))
            c.setFillColor(bellyC); c.fillOval(CGRect(x: 6, y: 7 + hover, width: 6, height: 4))
            c.setFillColor(bC); c.fillStrokeEllipse(CGRect(x: 11, y: 9 + hover, width: 5.5, height: 5))

            // beak
            c.setFillColor(beakC)
            var bkPts = [CGPoint(x: 16.5, y: 11 + hover), CGPoint(x: 18.5, y: 11.5 + hover), CGPoint(x: 16.5, y: 12.5 + hover)]
            var bkP = CGMutablePath()
            bkP.move(to: bkPts[0])
            for k in 1..<bkPts.count { bkP.addLine(to: bkPts[k]) }
            c.addPath(bkP); c.fillPath()

            // eye
            c.setFillColor(e); c.fillOval(CGRect(x: 13, y: 11.5 + hover, width: 1.5, height: 1.8))

            // wings
            c.setFillColor(bC); c.setStrokeColor(s)
            wing(c, side: -1, yB: 7 + hover, flapA: flap)
            wing(c, side: 1, yB: 7 + hover, flapA: -flap)

            // tail
            c.setStrokeColor(s); c.setLineWidth(1)
            c.move(to: CGPoint(x: 4, y: 8 + hover))
            c.addLine(to: CGPoint(x: 1.5, y: 7 + hover))
            c.addLine(to: CGPoint(x: 2, y: 9 + hover)); c.strokePath()

            // feet
            c.setFillColor(beakC)
            c.fillOval(CGRect(x: 7, y: 4 + hover, width: 1.5, height: 1))
            c.fillOval(CGRect(x: 10, y: 4 + hover, width: 1.5, height: 1))
        }
    }

    private static func wing(_ c: CGContext, side: Int, yB: CGFloat, flapA: CGFloat) {
        c.saveGState()
        c.translateBy(x: 9 + CGFloat(side) * 2, y: yB); c.rotate(by: flapA * 0.3)
        c.fillStrokeEllipse(CGRect(x: -2, y: -1, width: 4, height: 3))
        c.restoreGState()
    }
}

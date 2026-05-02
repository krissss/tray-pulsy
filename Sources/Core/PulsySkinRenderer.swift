import AppKit
import CoreGraphics

/// Generates animated pulse-waveform frames for the menu bar icon.
///
/// Visual style:
/// - **Colour** — configurable gradient themes (fire, ocean, matrix, neon, monochrome).
/// - **Amplitude** — scales with metric value (gentle at idle, dramatic under load).
/// - **Speed** — faster heartbeat under load (handled by TrayAnimator).
/// - **Waveform** — configurable style (ecg, sine, sawtooth, square, spike).
///
/// Uses a hospital-monitor sweep: bright "new" trace draws left→right,
/// dimmed "old" trace ahead of the cursor, separated by a small gap.
enum PulsySkinRenderer {

    // MARK: - Config

    static let frameCount = 24
    private static let iconSize: CGFloat = 18
    private static let scale: CGFloat = 2.0

    // Layout
    private static let centerY: CGFloat = 4    // baseline near bottom, peaks go up
    private static let dotRadius: CGFloat = 1.5

    // MARK: - Gradient colour

    /// Interpolate between two NSColors.
    private static func interpolate(from c1: NSColor, to c2: NSColor, fraction: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
        let f = max(0, min(1, fraction))
        return NSColor(
            red:   c1.redComponent   + (c2.redComponent   - c1.redComponent)   * f,
            green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * f,
            blue:  c1.blueComponent  + (c2.blueComponent  - c1.blueComponent)  * f,
            alpha: alpha
        )
    }

    /// Colour along the trace at normalised position `t` (0 = start, 1 = end) for a given theme.
    private static func gradientColor(at t: CGFloat, alpha: CGFloat = 1.0, theme: PulsyColorTheme) -> NSColor {
        let tt = max(0, min(1, t))
        let stops = theme.gradientStops
        // 3 stops: divide into 2 segments
        if tt < 0.5 {
            return interpolate(from: stops[0], to: stops[1], fraction: tt * 2, alpha: alpha)
        } else {
            return interpolate(from: stops[1], to: stops[2], fraction: (tt - 0.5) * 2, alpha: alpha)
        }
    }

    // MARK: - Amplitude helpers

    private static func amplitudeForValue(_ value: CGFloat, sensitivity: CGFloat) -> CGFloat {
        let base = 4.0 + sensitivity * 6.0              // 4~16 range based on sensitivity
        return base + clamp01(value / 100.0) * 3.0       // + small dynamic response to load
    }

    private static func rPeakForValue(_ value: CGFloat, sensitivity: CGFloat) -> CGFloat {
        let base = 0.6 + sensitivity * 0.5               // 0.6~1.6
        return base + clamp01(value / 100.0) * 0.3       // + small dynamic response
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }

    // MARK: - Public

    /// Generate all frames for one sweep cycle at the given metric value with default config.
    static func generateFrames(value: CGFloat = 0) -> [NSImage] {
        generateFrames(value: value, config: PulsyConfig.defaults)
    }

    /// Generate all frames for one sweep cycle at the given metric value and config.
    static func generateFrames(value: CGFloat, config: PulsyConfig) -> [NSImage] {
        let amp = amplitudeForValue(value, sensitivity: config.amplitudeSensitivity)
        let rPeak = rPeakForValue(value, sensitivity: config.amplitudeSensitivity)
        return (0..<frameCount).map { generateFrame($0, amp: amp, rPeak: rPeak, config: config) }
    }

    // MARK: - Frame generation

    private static func generateFrame(_ index: Int, amp: CGFloat, rPeak: CGFloat, config: PulsyConfig) -> NSImage {
        let pw = Int(iconSize * scale)
        let ph = Int(iconSize * scale)
        let cs = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return NSImage(size: NSSize(width: iconSize, height: iconSize))
        }

        ctx.scaleBy(x: scale, y: scale)

        let lineWidth = config.lineWidth
        let glowWidth = lineWidth * (2.0 + config.glowIntensity * 2.0)
        let gapWidth: CGFloat = lineWidth + 0.3

        if index == 0 {
            // Frame 0: full bright gradient waveform — thumbnail / preview
            drawGradientTrace(in: ctx, from: 0, to: iconSize,
                              amp: amp, rPeak: rPeak, alpha: 1.0,
                              lineWidth: lineWidth, glowWidth: glowWidth,
                              style: config.waveformStyle, theme: config.colorTheme)
        } else {
            let sweepX = CGFloat(index) / CGFloat(frameCount) * iconSize

            // Dimmed "old" trace (after the gap → right edge)
            let dimStart = sweepX + gapWidth
            if dimStart < iconSize {
                drawGradientTrace(in: ctx, from: dimStart, to: iconSize,
                                  amp: amp, rPeak: rPeak, alpha: 0.2,
                                  lineWidth: lineWidth, glowWidth: glowWidth,
                                  style: config.waveformStyle, theme: config.colorTheme)
            }

            // Bright "new" trace (left edge → sweep position)
            if sweepX > 0 {
                drawGradientTrace(in: ctx, from: 0, to: sweepX,
                                  amp: amp, rPeak: rPeak, alpha: 1.0,
                                  lineWidth: lineWidth, glowWidth: glowWidth,
                                  style: config.waveformStyle, theme: config.colorTheme)
            }

            // Bright dot at sweep position — colour matches the gradient at that x
            let tSweep = sweepX / iconSize
            let ySweep = centerY + waveformValue(at: tSweep, rPeak: rPeak, style: config.waveformStyle) * amp
            let dotColor = gradientColor(at: tSweep, theme: config.colorTheme).blended(withFraction: 0.4, of: .white) ?? .white
            ctx.setFillColor(dotColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: sweepX - dotRadius,
                                       y: ySweep - dotRadius,
                                       width: dotRadius * 2,
                                       height: dotRadius * 2))
        }

        guard let cg = ctx.makeImage() else {
            return NSImage(size: NSSize(width: iconSize, height: iconSize))
        }
        return NSImage(cgImage: cg, size: NSSize(width: iconSize, height: iconSize))
    }

    // MARK: - Gradient trace drawing

    /// Draw the waveform with per-segment gradient colour.
    private static func drawGradientTrace(
        in ctx: CGContext,
        from x0: CGFloat, to x1: CGFloat,
        amp: CGFloat, rPeak: CGFloat, alpha: CGFloat,
        lineWidth: CGFloat, glowWidth: CGFloat,
        style: PulsyWaveformStyle, theme: PulsyColorTheme
    ) {
        let step: CGFloat = 0.5
        var pts: [CGPoint] = []
        var x = x0
        while x <= x1 {
            let t = x / iconSize
            let y = centerY + waveformValue(at: t, rPeak: rPeak, style: style) * amp
            pts.append(CGPoint(x: x, y: y))
            x += step
        }
        guard pts.count > 1 else { return }

        // Glow pass — single colour (average), wider & transparent
        let midT = ((x0 + x1) * 0.5) / iconSize
        let glowCol = gradientColor(at: midT, alpha: alpha * 0.2, theme: theme)
        strokePath(pts, in: ctx, color: glowCol, width: glowWidth)

        // Main pass — pre-compute CGColor LUT, batch same-color segments
        let lutSize = 32
        var colorLUT = [CGColor]()
        colorLUT.reserveCapacity(lutSize)
        for i in 0..<lutSize {
            colorLUT.append(gradientColor(at: CGFloat(i) / CGFloat(lutSize - 1), alpha: alpha, theme: theme).cgColor)
        }

        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var currentLUT = lutIndex(for: pts[0].x / iconSize, count: lutSize)
        ctx.setStrokeColor(colorLUT[currentLUT])
        ctx.move(to: pts[0])

        for i in 1..<(pts.count - 1) {
            let nextLUT = lutIndex(for: pts[i].x / iconSize, count: lutSize)
            if nextLUT != currentLUT {
                // Flush the batch
                ctx.addLine(to: pts[i])
                ctx.strokePath()
                ctx.setStrokeColor(colorLUT[nextLUT])
                ctx.move(to: pts[i])
                currentLUT = nextLUT
            } else {
                ctx.addLine(to: pts[i])
            }
        }
        // Flush remaining
        ctx.addLine(to: pts[pts.count - 1])
        ctx.strokePath()
    }

    /// Quantize normalised position to LUT index.
    private static func lutIndex(for t: CGFloat, count: Int) -> Int {
        min(count - 1, max(0, Int(t * CGFloat(count - 1) + 0.5)))
    }

    private static func strokePath(
        _ pts: [CGPoint], in ctx: CGContext,
        color: NSColor, width: CGFloat
    ) {
        let path = CGMutablePath()
        path.move(to: pts[0])
        for i in 1..<pts.count { path.addLine(to: pts[i]) }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    // MARK: - Waveform dispatch

    /// Compute waveform value at normalised position `t` for the given style.
    static func waveformValue(at t: CGFloat, rPeak: CGFloat = 0.85, style: PulsyWaveformStyle) -> CGFloat {
        switch style {
        case .ecg:      return ecgValue(at: t, rPeak: rPeak)
        case .sine:     return sineValue(at: t, rPeak: rPeak)
        case .sawtooth: return sawtoothValue(at: t, rPeak: rPeak)
        case .square:   return squareValue(at: t, rPeak: rPeak)
        case .spike:    return spikeValue(at: t, rPeak: rPeak)
        }
    }

    // MARK: - Waveform implementations

    /// PQRST waveform.  `t` is normalised 0…1 = one heartbeat cycle.
    /// `rPeak` scales the R-spike intensity (0.6 … 1.5).
    static func ecgValue(at t: CGFloat, rPeak: CGFloat = 0.85) -> CGFloat {
        let p = t.truncatingRemainder(dividingBy: 1.0)
        let u = p < 0 ? p + 1.0 : p

        // P wave
        let pw = 0.45 * gauss(u, 0.10, 0.045)

        // QRS complex
        let q = -0.20 * gauss(u, 0.24, 0.013)
        let r =  rPeak * gauss(u, 0.27, 0.022)
        let s = -0.40 * gauss(u, 0.30, 0.015)

        // T wave
        let tw = 0.55 * gauss(u, 0.45, 0.060)

        return pw + q + r + s + tw
    }

    /// Simple sine wave. Output range ~0…1.
    private static func sineValue(at t: CGFloat, rPeak: CGFloat) -> CGFloat {
        let u = t.truncatingRemainder(dividingBy: 1.0)
        let phase = u < 0 ? u + 1.0 : u
        return rPeak * (0.5 + 0.5 * CGFloat(sin(Double(phase) * 2.0 * .pi)))
    }

    /// Sawtooth wave: linear rise then sharp fall. Output range ~0…1.
    private static func sawtoothValue(at t: CGFloat, rPeak: CGFloat) -> CGFloat {
        let u = t.truncatingRemainder(dividingBy: 1.0)
        let phase = u < 0 ? u + 1.0 : u
        if phase < 0.7 {
            return rPeak * (phase / 0.7)
        } else {
            return rPeak * (1.0 - (phase - 0.7) / 0.3) * 0.3
        }
    }

    /// Square wave: high plateau then low plateau. Output range ~0…1.
    private static func squareValue(at t: CGFloat, rPeak: CGFloat) -> CGFloat {
        let u = t.truncatingRemainder(dividingBy: 1.0)
        let phase = u < 0 ? u + 1.0 : u
        if phase < 0.4 {
            return rPeak
        } else if phase < 0.5 {
            return rPeak * (1.0 - (phase - 0.4) / 0.1)
        } else if phase < 0.9 {
            return 0
        } else {
            return rPeak * ((phase - 0.9) / 0.1)
        }
    }

    /// Spike: narrow Gaussian peak with flat baseline.
    private static func spikeValue(at t: CGFloat, rPeak: CGFloat) -> CGFloat {
        let u = t.truncatingRemainder(dividingBy: 1.0)
        let phase = u < 0 ? u + 1.0 : u
        // Sharp spike at center
        return rPeak * gauss(phase, 0.5, 0.04)
    }

    private static func gauss(_ x: CGFloat, _ mu: CGFloat, _ sigma: CGFloat) -> CGFloat {
        let d = (x - mu) / sigma
        return exp(-0.5 * d * d)
    }
}

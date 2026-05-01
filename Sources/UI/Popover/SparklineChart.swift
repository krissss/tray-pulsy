import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Sparkline Chart (Canvas-based)
// ═══════════════════════════════════════════════════════════════

/// Lightweight sparkline chart rendered via `Canvas`.
struct SparklineChart: View {
    let values: [Double]
    var color: Color = .accentColor
    var lineWidth: CGFloat = 1.5
    var showFill: Bool = true
    var showDot: Bool = true
    var showAnnotations: Bool = false
    /// Show current value label next to the last data point. Only effective when showAnnotations=true.
    var showCurrentValue: Bool = true
    /// Threshold zones: pairs of (upperBound, color). Drawn as horizontal bands.
    var thresholds: [(value: Double, color: Color)] = []
    /// Total time span in seconds (for time labels). 0 = hide time labels.
    var timeSpan: TimeInterval = 0

    // Layout constants shared with AnnotatedChartView hover overlay
    static let padLeft: CGFloat = 32
    static let padRight: CGFloat = 36
    static let padTop: CGFloat = 14
    static let padBottom: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }

            let lp = showAnnotations ? (showCurrentValue ? Self.padLeft : 20) : 0
            let rp = (showAnnotations && showCurrentValue) ? Self.padRight : 0
            let tp = showAnnotations ? Self.padTop : 0
            let bp = showAnnotations ? Self.padBottom : 0
            let chartW = size.width - lp - rp
            let chartH = size.height - tp - bp

            let (vMin, vMax) = bounds
            let range = vMax - vMin

            guard range > 0 else {
                let y = tp + chartH / 2
                let path = Path { p in
                    p.move(to: CGPoint(x: lp, y: y))
                    p.addLine(to: CGPoint(x: lp + chartW, y: y))
                }
                context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: lineWidth)
                return
            }

            let yFor: (Double) -> CGFloat = { v in
                tp + chartH - CGFloat((v - vMin) / range) * chartH
            }

            // Threshold zones
            for zone in thresholds {
                let y = yFor(min(zone.value, vMax))
                let rect = CGRect(x: lp, y: y, width: chartW, height: tp + chartH - y)
                context.fill(Path(rect), with: .color(zone.color.opacity(0.08)))
            }

            let points = values.enumerated().map { i, v in
                CGPoint(
                    x: lp + CGFloat(i) / CGFloat(Swift.max(values.count - 1, 1)) * chartW,
                    y: yFor(v)
                )
            }

            // Fill
            if showFill {
                let fillPath = Path { p in
                    p.move(to: CGPoint(x: points[0].x, y: tp + chartH))
                    for pt in points { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: points[points.count - 1].x, y: tp + chartH))
                    p.closeSubpath()
                }
                context.fill(fillPath, with: .color(color.opacity(0.12)))
            }

            // Line
            let linePath = Path { p in
                p.move(to: points[0])
                for i in 1..<points.count { p.addLine(to: points[i]) }
            }
            context.stroke(linePath, with: .color(color), lineWidth: lineWidth)

            // Latest-value dot
            if showDot, let last = points.last {
                context.fill(
                    Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)),
                    with: .color(color)
                )
            }

            guard showAnnotations else { return }

            // ── Annotations ──
            let font = Font.system(size: 9, weight: .regular, design: .monospaced)
            let textColor = Color.secondary

            // Current value (right of last point)
            if showCurrentValue, let last = points.last, let lastV = values.last {
                let text = Text(formatValue(lastV, max: vMax))
                    .font(font)
                    .foregroundStyle(color)
                context.draw(text, at: CGPoint(x: last.x + 8, y: last.y), anchor: .leading)
            }

            // Min / Max labels (left)
            let maxLabel = Text(formatValue(vMax, max: vMax)).font(font).foregroundStyle(textColor)
            context.draw(maxLabel, at: CGPoint(x: lp - 4, y: yFor(vMax)), anchor: .trailing)

            let minLabel = Text(formatValue(vMin, max: vMax)).font(font).foregroundStyle(textColor)
            context.draw(minLabel, at: CGPoint(x: lp - 4, y: yFor(vMin)), anchor: .trailing)

            // Time labels (bottom) — evenly spaced ticks
            if timeSpan > 0 {
                let timeFont = Font.system(size: 8, weight: .regular)
                let step = timeLabelStep(for: timeSpan)
                var t: TimeInterval = 0
                while t <= timeSpan + 1 {
                    let fraction = 1 - t / timeSpan
                    let x = lp + chartW * CGFloat(fraction)
                    let label = t == 0 ? "now" : formatTimeInterval(t)
                    let anchor: UnitPoint = t == 0 ? .trailing : t >= timeSpan ? .leading : .center
                    context.draw(
                        Text(label).font(timeFont).foregroundStyle(textColor),
                        at: CGPoint(x: x, y: tp + chartH + 8),
                        anchor: anchor
                    )
                    t += step
                }
            }
        }
    }

    private var bounds: (min: Double, max: Double) {
        let mn = values.min() ?? 0
        let mx = values.max() ?? 1
        return (mn, mx == mn ? mn + 1 : mx)
    }

    /// Choose time label interval so we get ~5-7 labels.
    private func timeLabelStep(for span: TimeInterval) -> TimeInterval {
        if span <= 120   { return 30 }
        if span <= 300   { return 60 }
        if span <= 900   { return 180 }
        if span <= 1800  { return 300 }  // 5 min → 7 labels
        if span <= 3600  { return 600 }  // 10 min → 7 labels
        return 1800
    }

    private func formatValue(_ v: Double, max: Double) -> String {
        if max >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if max >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }

    private func formatTimeInterval(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 { return "\(mins / 60)h" }
        if mins > 0 { return "\(mins)m" }
        return "\(Int(seconds))s"
    }
}

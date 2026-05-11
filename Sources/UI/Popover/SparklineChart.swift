import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Sparkline Chart (Canvas-based)
// ═══════════════════════════════════════════════════════════════

/// Lightweight sparkline chart rendered via `Canvas`.
struct SparklineChart: View {
    let values: [Double]
    var color: Color = .accentColor
    var secondaryValues: [Double]? = nil
    var secondaryColor: Color? = nil
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
            guard chartW > 0, chartH > 0 else { return }
            let plotRect = CGRect(x: lp, y: tp, width: chartW, height: chartH)
            let plotShape = Path(roundedRect: plotRect, cornerSize: CGSize(width: 6, height: 6))

            context.fill(plotShape, with: .color(.secondary.opacity(showAnnotations ? 0.025 : 0.035)))
            context.stroke(plotShape, with: .color(.secondary.opacity(0.06)), lineWidth: 0.5)

            let (vMin, vMax) = bounds
            let range = vMax - vMin

            guard range > 0 else {
                let y = tp + chartH / 2
                let path = Path { p in
                    p.move(to: CGPoint(x: lp, y: y))
                    p.addLine(to: CGPoint(x: lp + chartW, y: y))
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(0.5)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                return
            }

            let yFor: (Double) -> CGFloat = { v in
                tp + chartH - CGFloat((v - vMin) / range) * chartH
            }

            // Quiet guide lines for scanability without turning the sparkline into a full chart.
            if showAnnotations {
                for fraction in [CGFloat(0.25), CGFloat(0.5), CGFloat(0.75)] {
                    let y = tp + chartH * fraction
                    let guide = Path { p in
                        p.move(to: CGPoint(x: lp, y: y))
                        p.addLine(to: CGPoint(x: lp + chartW, y: y))
                    }
                    context.stroke(guide, with: .color(.secondary.opacity(0.08)), lineWidth: 0.5)
                }
            }

            // Threshold zones. Higher values are riskier, so color the area above each threshold.
            let sortedThresholds = thresholds
                .filter { $0.value > vMin && $0.value < vMax }
                .sorted { $0.value < $1.value }
            for index in sortedThresholds.indices {
                let zone = sortedThresholds[index]
                let lowerY = yFor(zone.value)
                let upperY = index + 1 < sortedThresholds.count
                    ? yFor(sortedThresholds[index + 1].value)
                    : tp
                let rect = CGRect(
                    x: lp,
                    y: min(upperY, lowerY),
                    width: chartW,
                    height: max(abs(lowerY - upperY), 1)
                )
                context.fill(Path(rect), with: .color(zone.color.opacity(showAnnotations ? 0.08 : 0.055)))
                if showAnnotations {
                    let thresholdLine = Path { p in
                        p.move(to: CGPoint(x: lp, y: lowerY))
                        p.addLine(to: CGPoint(x: lp + chartW, y: lowerY))
                    }
                    context.stroke(
                        thresholdLine,
                        with: .color(zone.color.opacity(0.24)),
                        style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
                    )
                }
            }

            let renderLimit = renderPointLimit(for: chartW)
            let primarySamples = downsample(values, limit: renderLimit)
            let secondarySamples = secondaryValues.map { downsample($0, limit: renderLimit) } ?? []
            let points = chartPoints(for: primarySamples, totalCount: values.count, x: lp, width: chartW, yFor: yFor)
            let secondaryPoints = chartPoints(
                for: secondarySamples,
                totalCount: secondaryValues?.count ?? 0,
                x: lp,
                width: chartW,
                yFor: yFor
            )

            // Fill
            if showFill {
                var fillPath = smoothedPath(for: points, yRange: tp...(tp + chartH))
                fillPath.addLine(to: CGPoint(x: points[points.count - 1].x, y: tp + chartH))
                fillPath.addLine(to: CGPoint(x: points[0].x, y: tp + chartH))
                fillPath.closeSubpath()
                let gradient = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [color.opacity(showAnnotations ? 0.20 : 0.24), color.opacity(0.015)]),
                    startPoint: CGPoint(x: lp, y: tp),
                    endPoint: CGPoint(x: lp, y: tp + chartH)
                )
                context.fill(fillPath, with: gradient)
            }

            // Line
            drawLine(
                points,
                color: color,
                width: lineWidth,
                in: &context,
                yRange: tp...(tp + chartH)
            )

            if !secondaryPoints.isEmpty, let secondaryColor = secondaryColor {
                drawLine(
                    secondaryPoints,
                    color: secondaryColor,
                    width: max(lineWidth - 0.25, 1.25),
                    in: &context,
                    yRange: tp...(tp + chartH)
                )
            }

            // Latest-value dot
            if showDot, let last = points.last {
                let dot = Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(color))
                context.stroke(dot, with: .color(.primary.opacity(0.12)), lineWidth: 1)
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
        let allValues = (values + (secondaryValues ?? [])).filter(\.isFinite)
        let dataMin = allValues.min() ?? 0
        let dataMax = allValues.max() ?? 1
        let upper = max(dataMax, 1)
        let lower = min(dataMin, 0)
        let range = max(upper - lower, upper * 0.18, 1)
        let paddedMin = lower < 0 ? lower - range * 0.1 : 0
        return (paddedMin, upper + range * 0.18)
    }

    private func renderPointLimit(for width: CGFloat) -> Int {
        let density: CGFloat = showAnnotations ? 0.9 : 0.55
        let cap = showAnnotations ? 260 : 160
        return min(max(Int(width * density), 48), cap)
    }

    private func chartPoints(
        for samples: [ChartSample],
        totalCount: Int,
        x: CGFloat,
        width: CGFloat,
        yFor: (Double) -> CGFloat
    ) -> [CGPoint] {
        let denominator = CGFloat(Swift.max(totalCount - 1, 1))
        return samples.map { sample in
            CGPoint(
                x: x + CGFloat(sample.index) / denominator * width,
                y: yFor(sample.value)
            )
        }
    }

    private func downsample(_ series: [Double], limit: Int) -> [ChartSample] {
        let sanitized = series.map { $0.isFinite ? $0 : 0 }
        guard sanitized.count > limit, limit >= 3 else {
            return sanitized.enumerated().map { ChartSample(index: $0.offset, value: $0.element) }
        }

        let bucketSize = Double(sanitized.count - 2) / Double(limit - 2)
        var samples = [ChartSample(index: 0, value: sanitized[0])]
        samples.reserveCapacity(limit)

        var anchorIndex = 0
        for bucket in 0..<(limit - 2) {
            let nextAverageStart = Int(floor(Double(bucket + 1) * bucketSize)) + 1
            let nextAverageEnd = min(Int(floor(Double(bucket + 2) * bucketSize)) + 1, sanitized.count)
            let averageRange = nextAverageStart..<max(nextAverageStart + 1, nextAverageEnd)

            let averageX: Double
            let averageY: Double
            if averageRange.lowerBound < sanitized.count {
                let clampedRange = averageRange.lowerBound..<min(averageRange.upperBound, sanitized.count)
                let count = Double(clampedRange.count)
                averageX = clampedRange.reduce(0) { $0 + Double($1) } / count
                averageY = clampedRange.reduce(0) { $0 + sanitized[$1] } / count
            } else {
                averageX = Double(sanitized.count - 1)
                averageY = sanitized[sanitized.count - 1]
            }

            let candidateStart = Int(floor(Double(bucket) * bucketSize)) + 1
            let candidateEnd = min(Int(floor(Double(bucket + 1) * bucketSize)) + 1, sanitized.count - 1)
            let candidateRange = candidateStart..<max(candidateStart + 1, candidateEnd)

            var selectedIndex = candidateStart
            var largestArea = -Double.infinity
            let anchorX = Double(anchorIndex)
            let anchorY = sanitized[anchorIndex]

            for index in candidateRange where index < sanitized.count {
                let area = abs(
                    (anchorX - averageX) * (sanitized[index] - anchorY)
                    - (anchorX - Double(index)) * (averageY - anchorY)
                )
                if area > largestArea {
                    largestArea = area
                    selectedIndex = index
                }
            }

            selectedIndex = min(max(selectedIndex, 0), sanitized.count - 1)
            samples.append(ChartSample(index: selectedIndex, value: sanitized[selectedIndex]))
            anchorIndex = selectedIndex
        }

        samples.append(ChartSample(index: sanitized.count - 1, value: sanitized[sanitized.count - 1]))
        return samples
    }

    private func drawLine(
        _ points: [CGPoint],
        color: Color,
        width: CGFloat,
        in context: inout GraphicsContext,
        yRange: ClosedRange<CGFloat>
    ) {
        guard !points.isEmpty else { return }
        let linePath = smoothedPath(for: points, yRange: yRange)
        context.stroke(
            linePath,
            with: .color(color.opacity(0.18)),
            style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            linePath,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func smoothedPath(for points: [CGPoint], yRange: ClosedRange<CGFloat>) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            guard points.count > 1 else { return }

            for index in 0..<(points.count - 1) {
                let previous = index > 0 ? points[index - 1] : points[index]
                let current = points[index]
                let next = points[index + 1]
                let following = index + 2 < points.count ? points[index + 2] : next

                let control1 = CGPoint(
                    x: current.x + (next.x - previous.x) / 9,
                    y: (current.y + (next.y - previous.y) / 9).clamped(to: yRange)
                )
                let control2 = CGPoint(
                    x: next.x - (following.x - current.x) / 9,
                    y: (next.y - (following.y - current.y) / 9).clamped(to: yRange)
                )
                path.addCurve(to: next, control1: control1, control2: control2)
            }
        }
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

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct ChartSample {
    let index: Int
    let value: Double
}

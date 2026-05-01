import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Annotated Chart with Hover Tooltip
// ═══════════════════════════════════════════════════════════════

/// Full-featured metric chart with optional min/max labels, time axis, threshold zones,
/// and a hover tooltip that shows the exact timestamp + value at the cursor.
struct AnnotatedChartView: View {
    let values: [Double]
    let timestamps: [Date]
    var color: Color = .accentColor
    var thresholds: [(value: Double, color: Color)] = []
    var timeSpan: TimeInterval = 1800
    var valueFormatter: (Double) -> String = { String(format: "%.0f", $0) }
    var chartHeight: CGFloat = 80
    var showAnnotations: Bool = true
    var showCurrentValue: Bool = true

    @State private var hoverIndex: Int? = nil
    @State private var viewSize: CGSize = .zero

    private var lp: CGFloat { showAnnotations ? (showCurrentValue ? SparklineChart.padLeft : 20) : 4 }
    private var rp: CGFloat { (showAnnotations && showCurrentValue) ? SparklineChart.padRight : 4 }
    private var tp: CGFloat { showAnnotations ? SparklineChart.padTop : 0 }
    private var bp: CGFloat { showAnnotations ? SparklineChart.padBottom : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SparklineChart(
                values: values,
                color: color,
                lineWidth: 2,
                showFill: true,
                showDot: hoverIndex == nil,
                showAnnotations: showAnnotations,
                showCurrentValue: showCurrentValue,
                thresholds: thresholds,
                timeSpan: timeSpan
            )
            .frame(height: chartHeight)

            // Hover overlay
            if let idx = hoverIndex, values.indices.contains(idx), viewSize.width > 0 {
                hoverContents(at: idx)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            }
        )
        .frame(height: chartHeight + bp)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hoverIndex = indexAt(point)
            case .ended:
                hoverIndex = nil
            }
        }
    }

    // MARK: - Index mapping

    private func indexAt(_ point: CGPoint) -> Int? {
        let chartW = viewSize.width - lp - rp
        guard chartW > 0, !values.isEmpty else { return nil }
        let relX = point.x - lp
        guard relX >= 0, relX <= chartW else { return nil }
        let fraction = relX / chartW
        return Int(round(fraction * Double(values.count - 1)))
    }

    // MARK: - Hover overlay

    @ViewBuilder
    private func hoverContents(at idx: Int) -> some View {
        let chartW = viewSize.width - lp - rp
        let chartH = chartHeight - tp
        let (vMin, vMax) = chartBounds
        let range = vMax - vMin

        if range > 0 {
            let v = values[idx]
            let x = lp + CGFloat(idx) / CGFloat(Swift.max(values.count - 1, 1)) * chartW
            let y = tp + chartH - CGFloat((v - vMin) / range) * chartH

            ZStack {
                // Vertical indicator line
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(width: 1, height: chartH)
                    .position(x: x, y: tp + chartH / 2)

                // Dot at data point
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .position(x: x, y: y)

                // Tooltip bubble
                tooltipBubble(time: Self.timeFormatter.string(from: timestamps[idx]),
                              value: valueFormatter(v), anchorX: x, dotY: y)
            }
        }
    }

    @ViewBuilder
    private func tooltipBubble(time: String, value: String, anchorX: CGFloat, dotY: CGFloat) -> some View {
        let tooltipW: CGFloat = 90
        let tooltipH: CGFloat = 36
        let clampedX = min(max(anchorX, lp + tooltipW / 2), viewSize.width - rp - tooltipW / 2)
        let above = dotY - tooltipH / 2 - 12
        let below = dotY + tooltipH / 2 + 12
        let tooltipY = above >= tp ? above : below

        VStack(spacing: 2) {
            Text(time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .frame(width: tooltipW)
        .position(x: clampedX, y: tooltipY)
    }

    // MARK: - Helpers

    private var chartBounds: (min: Double, max: Double) {
        let mn = values.min() ?? 0
        let mx = values.max() ?? 1
        return (mn, mx == mn ? mn + 1 : mx)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

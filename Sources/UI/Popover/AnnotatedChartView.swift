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
    var secondaryValues: [Double]? = nil
    var secondaryColor: Color? = nil
    var thresholds: [(value: Double, color: Color)] = []
    var timeSpan: TimeInterval = 1800
    var valueFormatter: (Double) -> String = { String(format: "%.0f", $0) }
    var primaryValuePrefix: String? = nil
    var secondaryValuePrefix: String? = nil
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
                secondaryValues: secondaryValues,
                secondaryColor: secondaryColor,
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
        let chartH = chartHeight - tp - bp
        let (vMin, vMax) = chartBounds
        let range = vMax - vMin

        if range > 0 {
            let v = values[idx]
            let secondaryIndex = secondaryIndex(forPrimaryIndex: idx)
            let secondaryValue = secondaryIndex.flatMap { secondaryValues?[$0] }
            let x = lp + CGFloat(idx) / CGFloat(Swift.max(values.count - 1, 1)) * chartW
            let y = tp + chartH - CGFloat((v - vMin) / range) * chartH
            let timestamp = timestamps.indices.contains(idx)
                ? Self.timeFormatter.string(from: timestamps[idx])
                : ""

            ZStack {
                // Vertical indicator line
                Rectangle()
                    .fill(color.opacity(0.24))
                    .frame(width: 1, height: chartH)
                    .position(x: x, y: tp + chartH / 2)

                // Dot at data point
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .shadow(color: color.opacity(0.28), radius: 4)
                    .position(x: x, y: y)

                if let secondaryValue, let secondaryColor {
                    let secondaryY = tp + chartH - CGFloat((secondaryValue - vMin) / range) * chartH
                    Circle()
                        .fill(secondaryColor)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .shadow(color: secondaryColor.opacity(0.22), radius: 4)
                        .position(x: x, y: secondaryY)
                }

                // Tooltip bubble
                tooltipBubble(
                    time: timestamp,
                    primaryValue: prefixedValue(valueFormatter(v), prefix: primaryValuePrefix),
                    secondaryValue: secondaryValue.map {
                        prefixedValue(valueFormatter($0), prefix: secondaryValuePrefix)
                    },
                    anchorX: x,
                    dotY: y
                )
            }
        }
    }

    @ViewBuilder
    private func tooltipBubble(
        time: String,
        primaryValue: String,
        secondaryValue: String?,
        anchorX: CGFloat,
        dotY: CGFloat
    ) -> some View {
        let tooltipW: CGFloat = secondaryValue == nil ? 90 : 118
        let tooltipH: CGFloat = secondaryValue == nil ? 36 : 52
        let clampedX = min(max(anchorX, lp + tooltipW / 2), viewSize.width - rp - tooltipW / 2)
        let above = dotY - tooltipH / 2 - 12
        let below = dotY + tooltipH / 2 + 12
        let tooltipY = above >= tp ? above : below

        VStack(spacing: 2) {
            Text(time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(primaryValue)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            if let secondaryValue {
                Text(secondaryValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondaryColor ?? .secondary)
            }
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
        let allValues = values + (secondaryValues ?? [])
        let dataMin = allValues.min() ?? 0
        let dataMax = allValues.max() ?? 1
        let upper = max(dataMax, 1)
        let lower = min(dataMin, 0)
        let range = max(upper - lower, upper * 0.18, 1)
        let paddedMin = lower < 0 ? lower - range * 0.1 : 0
        return (paddedMin, upper + range * 0.18)
    }

    private func secondaryIndex(forPrimaryIndex index: Int) -> Int? {
        guard let secondaryValues, !secondaryValues.isEmpty else { return nil }
        let fraction = Double(index) / Double(Swift.max(values.count - 1, 1))
        let secondaryIndex = Int(round(fraction * Double(Swift.max(secondaryValues.count - 1, 0))))
        return min(max(secondaryIndex, 0), secondaryValues.count - 1)
    }

    private func prefixedValue(_ value: String, prefix: String?) -> String {
        guard let prefix else { return value }
        return "\(prefix) \(value)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

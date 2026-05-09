import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Metric Chart Row (shared by Popover + Overview)
// ═══════════════════════════════════════════════════════════════

/// A metric row with icon, label, value text, and an annotated trend chart.
/// Used by both the popover metrics panel and the Overview settings tab.
struct MetricChartRow: View {
    let icon: String
    let label: String
    let valueText: String
    var subtitle: String? = nil
    let values: [Double]
    let timestamps: [Date]
    let color: Color
    var thresholds: [(value: Double, color: Color)] = []
    var valueFormatter: (Double) -> String = { String(format: "%.0f%%", $0) }
    var chartHeight: CGFloat = 64
    var iconSize: CGFloat = 28
    var compact: Bool = false
    var timeSpan: TimeInterval = 1800
    var showCurrentValue: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            // Label row
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(color)
                    .frame(width: iconSize, height: iconSize)
                    .if(!compact) { $0.glassEffect(.regular, in: .circle) }
                    .accessibilityHidden(true)

                Text(label)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(compact ? .primary : .secondary)
                Spacer()

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(valueText)
                    .font(compact
                          ? .system(.caption, design: .monospaced).bold()
                          : .system(.body, design: .rounded).monospacedDigit().bold())
                    .foregroundStyle(compact ? .primary : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, compact ? 6 : 0)
                    .padding(.vertical, compact ? 3 : 0)
                    .background {
                        if compact {
                            Capsule(style: .continuous)
                                .fill(color.opacity(0.12))
                        }
                    }
            }

            // Chart
            if !values.isEmpty {
                AnnotatedChartView(
                    values: values,
                    timestamps: timestamps,
                    color: color,
                    thresholds: thresholds,
                    timeSpan: timeSpan,
                    valueFormatter: valueFormatter,
                    chartHeight: chartHeight,
                    showAnnotations: true,
                    showCurrentValue: showCurrentValue
                )
                .padding(.leading, 0)
            }
        }
        .padding(.vertical, compact ? 7 : 8)
        .padding(.horizontal, compact ? 8 : 0)
        .background {
            if compact {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            }
        }
        .overlay {
            if compact {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.10), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(valueText)")
    }
}

// MARK: - View modifier helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

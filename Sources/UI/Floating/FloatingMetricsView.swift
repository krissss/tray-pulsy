import AppKit
import Defaults
import SwiftUI

struct FloatingMetricsView: View {
    let systemMonitor: SystemMonitor
    let skinFrameView: FloatingSkinFrameView
    let openSettings: () -> Void
    let hideWindow: () -> Void

    @Default(.floatingWindowMetricItems) private var floatingWindowMetricItems
    @Default(.metricMonitorItems) private var metricMonitorItems
    @Default(.floatingWindowMetricsLayout) private var metricsLayout
    @Default(.floatingWindowShowsSkin) private var showsSkin
    @Default(.floatingWindowBackgroundColor) private var backgroundColor
    @Default(.floatingWindowBackgroundOpacity) private var backgroundOpacity
    @Default(.floatingWindowTextColor) private var textColor
    @Default(.thresholds) private var thresholds

    private var items: [MetricDisplayItem] {
        let selected = FloatingMetricsSelection.displayedItems(
            stored: floatingWindowMetricItems,
            monitored: metricMonitorItems
        )
        return MetricDisplayItem.allCases.filter { selected.contains($0) }
    }

    var body: some View {
        content
            .padding(FloatingMetricsLayoutMetrics.padding)
            .background {
                RoundedRectangle(cornerRadius: FloatingMetricsLayoutMetrics.cornerRadius, style: .continuous)
                    .fill(backgroundColor.color.opacity(min(max(backgroundOpacity, 0), 1)))
            }
            .contextMenu {
                Button(L10n.popoverOpenMainWindow, action: openSettings)
                Button(L10n.floatingWindowHide, action: hideWindow)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.floatingWindowHeader)
    }

    @ViewBuilder
    private var content: some View {
        // 图标位置与指标排列是两个正交的轴：图标在上/在左由档位决定，
        // 指标自己横排还是竖排由 `stacksMetricsVertically` 决定。
        if metricsLayout.placesIconAboveMetrics {
            VStack(alignment: .center, spacing: showsSkin ? FloatingMetricsLayoutMetrics.skinGap : 0) {
                skinIcon
                metricsArea
            }
        } else {
            HStack(alignment: .center, spacing: showsSkin ? FloatingMetricsLayoutMetrics.skinGap : 0) {
                skinIcon
                metricsArea
            }
        }
    }

    @ViewBuilder
    private var skinIcon: some View {
        if showsSkin {
            FloatingSkinFrameRepresentable(frameView: skinFrameView)
                .frame(
                    width: FloatingMetricsLayoutMetrics.skinSize,
                    height: FloatingMetricsLayoutMetrics.skinSize
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var metricsArea: some View {
        if metricsLayout.stacksMetricsVertically {
            VStack(alignment: .leading, spacing: FloatingMetricsLayoutMetrics.verticalItemSpacing) {
                ForEach(items) { item in
                    FloatingMetricRow(
                        item: item,
                        valueText: valueText(for: item),
                        valueColor: valueColor(for: item),
                        textColor: textColor.color
                    )
                }
            }
        } else {
            HStack(alignment: .center, spacing: FloatingMetricsLayoutMetrics.horizontalItemSpacing) {
                ForEach(items) { item in
                    FloatingMetricColumn(
                        item: item,
                        valueText: valueText(for: item),
                        valueColor: valueColor(for: item),
                        textColor: textColor.color
                    )
                }
            }
        }
    }

    private func valueText(for item: MetricDisplayItem) -> String {
        let value = item.formatValue(from: systemMonitor).trimmingCharacters(in: .whitespaces)
        switch item {
        case .networkDown, .networkUp:
            return "\(value)/s"
        case .cpu, .gpu, .memory, .disk:
            return value
        }
    }

    private func valueColor(for item: MetricDisplayItem) -> Color {
        guard let override = item.thresholdColor(
            forRawValue: item.rawValue(from: systemMonitor),
            thresholds: thresholds
        ) else {
            return textColor.color
        }
        return Color(nsColor: override)
    }
}

private struct FloatingMetricColumn: View {
    let item: MetricDisplayItem
    let valueText: String
    let valueColor: Color
    let textColor: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(item.shortLabel)
                .font(.system(size: FloatingMetricsLayoutMetrics.labelFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(valueText)
                .font(.system(size: FloatingMetricsLayoutMetrics.valueFontSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(
            width: FloatingMetricsLayoutMetrics.horizontalMetricWidth,
            height: FloatingMetricsLayoutMetrics.horizontalMetricHeight
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName) \(valueText)")
    }
}

private struct FloatingMetricRow: View {
    let item: MetricDisplayItem
    let valueText: String
    let valueColor: Color
    let textColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FloatingMetricsLayoutMetrics.verticalLabelValueSpacing) {
            Text(item.shortLabel)
                .font(.system(size: FloatingMetricsLayoutMetrics.labelFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor.opacity(0.72))
                .lineLimit(1)
                .frame(width: FloatingMetricsLayoutMetrics.verticalLabelWidth, alignment: .leading)

            Text(valueText)
                .font(.system(size: FloatingMetricsLayoutMetrics.valueFontSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: FloatingMetricsLayoutMetrics.verticalValueWidth, alignment: .trailing)
        }
        .frame(height: FloatingMetricsLayoutMetrics.verticalMetricHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName) \(valueText)")
    }
}

struct FloatingSkinFrameRepresentable: NSViewRepresentable {
    let frameView: FloatingSkinFrameView

    func makeNSView(context: Context) -> FloatingSkinFrameView {
        frameView
    }

    func updateNSView(_ nsView: FloatingSkinFrameView, context: Context) {}
}

final class FloatingSkinFrameView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: FloatingMetricsLayoutMetrics.skinSize,
            height: FloatingMetricsLayoutMetrics.skinSize
        )
    }

    init() {
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: FloatingMetricsLayoutMetrics.skinSize,
            height: FloatingMetricsLayoutMetrics.skinSize
        ))
        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.masksToBounds = true
    }

    func setFrameImage(_ image: NSImage?) {
        guard image !== self.image else { return }
        self.image = image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = self.image else { return }
        let box = bounds
        let src = image.size
        guard src.width > 0, src.height > 0 else { return }
        // Same relative sizing as every other surface + the web preview.
        let dest = SkinSizing.displaySize(source: src, box: box.size)
        let destW = dest.width
        let destH = dest.height
        let drawRect = NSRect(
            x: (box.width - destW) / 2,
            y: (box.height - destH) / 2,
            width: destW,
            height: destH
        )
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        image.draw(in: drawRect)
        ctx?.imageInterpolation = prev ?? .none
    }
}

enum FloatingMetricsLayoutMetrics {
    static let padding: CGFloat = 6
    static let cornerRadius: CGFloat = 11
    static let skinSize: CGFloat = 22
    static let skinGap: CGFloat = 5
    static let horizontalItemSpacing: CGFloat = 3
    static let verticalItemSpacing: CGFloat = 2
    static let verticalLabelValueSpacing: CGFloat = 4
    static let horizontalMetricWidth: CGFloat = 31
    static let horizontalMetricHeight: CGFloat = 22
    static let verticalLabelWidth: CGFloat = 21
    static let verticalValueWidth: CGFloat = 32
    static let verticalMetricHeight: CGFloat = 13
    static let labelFontSize: CGFloat = 7
    static let valueFontSize: CGFloat = 10

    static var verticalMetricWidth: CGFloat {
        verticalLabelWidth + verticalLabelValueSpacing + verticalValueWidth
    }
}

import AppKit

/// Custom NSView that renders animation icon + metric text via Core Graphics.
/// Replaces NSAttributedString-based button title for zero-allocation per-tick rendering.
final class StatusBarView: NSView {

    // MARK: - Cached fonts
    private let labelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .light)
    private let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

    // MARK: - State
    private(set) var currentFrame: NSImage?
    private var items: [MetricDisplayItem] = []
    private var values: [String] = []
    private var colors: [NSColor] = []
    private var columnXPositions: [CGFloat] = []  // cached per-column X start positions
    private var columnWidths: [CGFloat] = []       // cached per-column widths

    // MARK: - Cached attributed strings (rebuilt only when values/items change)
    private var cachedLabels: [NSAttributedString] = []
    private var cachedLabelX: [CGFloat] = []
    private var cachedValues: [NSAttributedString] = []
    private var cachedValueX: [CGFloat] = []

    private let iconSize: CGFloat = 22
    private let textLeftPadding: CGFloat = 3
    private let columnGap: CGFloat = 6
    private let menuBarHeight: CGFloat = 22

    // MARK: - Public API

    /// Update the animation frame image. Called up to 40x/sec by TrayAnimator.
    /// Skips redraw if the image pointer hasn't changed.
    func setFrameImage(_ image: NSImage?) {
        guard image !== currentFrame else { return }
        currentFrame = image
        needsDisplay = true
    }

    /// Call when selected metric items change. Recalculates column layout.
    func setItems(_ newItems: [MetricDisplayItem], sampleValues: [String], colors: [NSColor]) {
        guard newItems.map(\.rawValue) != items.map(\.rawValue) else { return }
        items = newItems
        values = sampleValues
        self.colors = colors
        recalculateLayout()
        rebuildAttributedStringCache()
        needsDisplay = true
    }

    /// Call every tick with new values. Triggers redraw only if values changed.
    func updateValues(_ newValues: [String], colors: [NSColor]) {
        guard newValues != values || colors != self.colors else { return }
        values = newValues
        self.colors = colors
        rebuildAttributedStringCache()
        needsDisplay = true
    }

    /// Clear all metric text (display turned off).
    func clear() {
        items = []
        values = []
        colors = []
        columnXPositions = []
        columnWidths = []
        cachedLabels = []
        cachedLabelX = []
        cachedValues = []
        cachedValueX = []
        needsDisplay = true
    }

    // MARK: - Layout

    private func recalculateLayout() {
        var positions: [CGFloat] = []
        var widths: [CGFloat] = []
        let startX = iconSize + textLeftPadding

        var x: CGFloat = startX
        for i in items.indices {
            let labelW = (items[i].shortLabel as NSString).size(withAttributes: [.font: labelFont]).width
            let fallbackValue = values.indices.contains(i) ? values[i] : "99.9M"
            let valueW = (fallbackValue as NSString).size(withAttributes: [.font: valueFont]).width
            let colW = max(labelW, valueW) + columnGap

            positions.append(x)
            widths.append(colW)
            x += colW
        }
        columnXPositions = positions
        columnWidths = widths
    }

    /// Rebuild cached NSAttributedString + centered X positions.
    /// Called only when items or values change (not on every animation frame).
    private func rebuildAttributedStringCache() {
        var labels: [NSAttributedString] = []
        var labelXs: [CGFloat] = []
        var vals: [NSAttributedString] = []
        var valXs: [CGFloat] = []

        for i in items.indices {
            let x = columnXPositions[i]
            let colW = columnWidths[i]

            let labelStr = NSAttributedString(
                string: items[i].shortLabel,
                attributes: [.font: labelFont, .foregroundColor: NSColor.labelColor]
            )
            let labelW = labelStr.size().width
            labels.append(labelStr)
            labelXs.append(x + (colW - labelW) / 2)

            let valueStr = NSAttributedString(
                string: values.indices.contains(i) ? values[i] : "",
                attributes: [.font: valueFont, .foregroundColor: colors.indices.contains(i) ? colors[i] : .textColor]
            )
            let valueW = valueStr.size().width
            vals.append(valueStr)
            valXs.append(x + (colW - valueW) / 2)
        }
        cachedLabels = labels
        cachedLabelX = labelXs
        cachedValues = vals
        cachedValueX = valXs
    }

    /// Returns the required status item width.
    var requiredWidth: CGFloat {
        if items.isEmpty { return iconSize }
        let textWidth = columnXPositions.last.map { $0 + (columnWidths.last ?? 0) - iconSize - textLeftPadding } ?? 0
        return iconSize + textLeftPadding + textWidth
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 1. Draw animation frame (left side)
        if let frame = currentFrame {
            let iconY = (menuBarHeight - iconSize) / 2
            frame.draw(in: NSRect(x: 0, y: iconY, width: iconSize, height: iconSize))
        }

        // 2. Draw cached metric strings (zero allocation in draw)
        guard !cachedLabels.isEmpty else { return }

        for i in cachedLabels.indices {
            cachedLabels[i].draw(at: NSPoint(x: cachedLabelX[i], y: 13))
            cachedValues[i].draw(at: NSPoint(x: cachedValueX[i], y: -1))
        }
    }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: iconSize, height: menuBarHeight))
    }

    required init?(coder: NSCoder) {
        super.init(frame: NSRect(x: 0, y: 0, width: iconSize, height: menuBarHeight))
    }
}

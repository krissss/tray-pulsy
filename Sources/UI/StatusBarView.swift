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
    /// Per-value threshold overrides; `nil` means "within normal range" and falls back
    /// to `textColor`. Mirrors the floating window's behaviour so both surfaces show the
    /// user-selected color normally and switch to yellow/red only past a threshold.
    private var valueOverrideColors: [NSColor?] = []
    private var columnXPositions: [CGFloat] = []  // cached per-column X start positions
    private var columnWidths: [CGFloat] = []       // cached per-column widths
    /// 生效的文字颜色，标签与数值统一使用。
    private var textColor: NSColor = .labelColor

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
    ///
    /// Also re-syncs when only the threshold overrides changed, so a caller that keeps the
    /// same item set but crosses a threshold cannot be left showing stale colors.
    func setItems(
        _ newItems: [MetricDisplayItem],
        sampleValues: [String],
        valueOverrideColors: [NSColor?]
    ) {
        guard newItems.map(\.rawValue) != items.map(\.rawValue)
            || valueOverrideColors != self.valueOverrideColors
        else { return }
        items = newItems
        values = sampleValues
        self.valueOverrideColors = valueOverrideColors
        recalculateLayout()
        rebuildAttributedStringCache()
        needsDisplay = true
    }

    /// Call every tick with new values. Triggers redraw only if values or threshold
    /// overrides changed — an unchanged tick must not rebuild attributed strings.
    func updateValues(_ newValues: [String], valueOverrideColors: [NSColor?]) {
        guard newValues != values || valueOverrideColors != self.valueOverrideColors else { return }
        values = newValues
        self.valueOverrideColors = valueOverrideColors
        rebuildAttributedStringCache()
        needsDisplay = true
    }

    /// Clear all metric text (display turned off).
    func clear() {
        items = []
        values = []
        valueOverrideColors = []
        columnXPositions = []
        columnWidths = []
        cachedLabels = []
        cachedLabelX = []
        cachedValues = []
        cachedValueX = []
        needsDisplay = true
    }

    /// Update the effective text color (used for labels and values).
    func setTextColor(_ color: NSColor) {
        guard color != textColor else { return }
        textColor = color
        if !cachedLabels.isEmpty {
            rebuildAttributedStringCache()
        }
        needsDisplay = true
    }

    // MARK: - Test Support

    /// Foreground colors currently baked into the cached attributed strings, in column
    /// order. Read-only and side-effect free; exists so unit tests can assert that both
    /// the base text color and the per-value threshold overrides actually reach the
    /// strings that get drawn (the previous `colors` removal was untested).
    var renderedForegroundColors: (labels: [NSColor], values: [NSColor]) {
        func colors(of strings: [NSAttributedString]) -> [NSColor] {
            strings.compactMap { string in
                guard string.length > 0 else { return nil }
                return string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            }
        }
        return (colors(of: cachedLabels), colors(of: cachedValues))
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
                attributes: [.font: labelFont, .foregroundColor: textColor]
            )
            let labelW = labelStr.size().width
            labels.append(labelStr)
            labelXs.append(x + (colW - labelW) / 2)

            let valueStr = NSAttributedString(
                string: values.indices.contains(i) ? values[i] : "",
                attributes: [
                    .font: valueFont,
                    .foregroundColor: valueOverrideColors.indices.contains(i)
                        ? (valueOverrideColors[i] ?? textColor)
                        : textColor
                ]
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
            let box = NSRect(x: 0, y: iconY, width: iconSize, height: iconSize)
            let src = frame.size
            if src.width > 0, src.height > 0 {
                // Contain within the icon box, preserving aspect ratio so
                // non-square sprites are not stretched. ALSO CAP the upscale so
                // small sprites keep their RELATIVE size instead of being blown
                // up to fill the box: a 15px Mario must look smaller than a 38px
                // Sonic. This mirrors the web preview (preview.js) which renders
                // `natural × min(K=3, CAP=92/w, CAP/h)` — i.e. the "max native
                // size left at 1:1" is 92/3 ≈ 30.67px. We scale that reference
                // to this box via the same ratio, so every sprite occupies the
                // same fraction of its display box as it does in the web gallery.
                // Same relative sizing as every other surface + the web preview.
                let dest = SkinSizing.displaySize(source: src, box: box.size)
                let destW = dest.width
                let destH = dest.height
                let drawRect = NSRect(
                    x: box.origin.x + (box.width - destW) / 2,
                    y: box.origin.y + (box.height - destH) / 2,
                    width: destW,
                    height: destH
                )
                // Nearest-neighbour keeps retro pixel-art sprites crisp.
                let ctx = NSGraphicsContext.current
                let prevInterp = ctx?.imageInterpolation
                ctx?.imageInterpolation = .none
                frame.draw(in: drawRect)
                ctx?.imageInterpolation = prevInterp ?? .none
            }
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

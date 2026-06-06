import AppKit
import Defaults
import SwiftUI

@MainActor
final class FloatingMetricsPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let openSettings: () -> Void
    private let skinFrameView = FloatingSkinFrameView()
    private var panel: NSPanel?

    init(appState: AppState, openSettings: @escaping () -> Void) {
        self.appState = appState
        self.openSettings = openSettings
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        applyWindowSettings()
        reloadContent()
        panel.orderFrontRegardless()
    }

    func close() {
        guard let panel else { return }
        savePlacement(for: panel)
        panel.delegate = nil
        panel.contentView = nil
        panel.close()
        self.panel = nil
    }

    func applyWindowSettings() {
        guard let panel else { return }
        panel.level = Defaults[.floatingWindowAlwaysOnTop] ? .floating : .normal
        resizePanelToFitSelection(panel)
    }

    func setFrameImage(_ image: NSImage?) {
        skinFrameView.setFrameImage(image)
    }

    func reloadContent() {
        guard let panel else { return }
        let hostingView = NSHostingView(
            rootView: FloatingMetricsView(
                systemMonitor: appState.systemMonitor,
                skinFrameView: skinFrameView,
                openSettings: { [weak self] in self?.openSettings() },
                hideWindow: {
                    Defaults[.floatingWindowEnabled] = false
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        savePlacement(for: panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        savePlacement(for: panel)
    }

    private func makePanel() -> NSPanel {
        let frame = initialFrame(for: Self.contentSize())
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func resizePanelToFitSelection(_ panel: NSPanel) {
        let size = Self.contentSize()
        guard panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(constrained(frame), display: true, animate: true)
    }

    private func initialFrame(for size: NSSize) -> NSRect {
        let placement = Defaults[.floatingWindowPlacement]
        if placement.hasSavedFrame {
            return constrained(
                NSRect(
                    x: placement.x,
                    y: placement.y,
                    width: size.width,
                    height: size.height
                )
            )
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.maxX - size.width - 24,
            y: screen.maxY - size.height - 48,
            width: size.width,
            height: size.height
        )
    }

    private func constrained(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(frame.minX, screen.minX + 8), screen.maxX - frame.width - 8)
        let y = min(max(frame.minY, screen.minY + 8), screen.maxY - frame.height - 8)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func savePlacement(for panel: NSPanel) {
        let frame = panel.frame
        Defaults[.floatingWindowPlacement] = FloatingWindowPlacement(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    static func columnCount(for itemCount: Int) -> Int {
        min(max(itemCount, 1), 3)
    }

    static func contentSize() -> NSSize {
        let selectedItems = Defaults[.floatingWindowMetricItems].isEmpty
            ? Defaults.Keys.defaultFloatingWindowMetricItems
            : Defaults[.floatingWindowMetricItems]
        let count = max(selectedItems.count, 1)
        let showsSkin = Defaults[.floatingWindowShowsSkin]
        let padding = FloatingMetricsLayoutMetrics.padding * 2
        let skinWidth = showsSkin ? FloatingMetricsLayoutMetrics.skinSize : 0
        let skinGap = showsSkin && count > 0 ? FloatingMetricsLayoutMetrics.skinGap : 0

        let width: CGFloat
        let height: CGFloat
        switch Defaults[.floatingWindowMetricsLayout] {
        case .horizontal:
            let metricWidth = CGFloat(count) * FloatingMetricsLayoutMetrics.horizontalMetricWidth
                + CGFloat(max(count - 1, 0)) * FloatingMetricsLayoutMetrics.horizontalItemSpacing
            width = padding + skinWidth + skinGap + metricWidth
            height = padding + max(skinWidth, FloatingMetricsLayoutMetrics.horizontalMetricHeight)
        case .vertical:
            let metricHeight = CGFloat(count) * FloatingMetricsLayoutMetrics.verticalMetricHeight
                + CGFloat(max(count - 1, 0)) * FloatingMetricsLayoutMetrics.verticalItemSpacing
            width = padding + skinWidth + skinGap + FloatingMetricsLayoutMetrics.verticalMetricWidth
            height = padding + max(skinWidth, metricHeight)
        }
        return NSSize(width: width, height: height)
    }
}

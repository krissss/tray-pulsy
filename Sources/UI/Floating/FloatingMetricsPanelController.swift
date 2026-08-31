import AppKit
import Defaults
import SwiftUI

@MainActor
final class FloatingMetricsPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let openSettings: () -> Void
    private let popoverPresenter: MetricsPopoverPresenter
    private let skinFrameView = FloatingSkinFrameView()
    private var panel: NSPanel?
    private var popoverAnchorView: FloatingPopoverAnchorView?
    private var localMouseMonitor: Any?
    private var mouseDownLocation: NSPoint?
    private var didDragSinceMouseDown = false
    private var pendingSingleClickTask: Task<Void, Never>?

    private static let clickMovementTolerance: CGFloat = 4

    init(
        appState: AppState,
        openSettings: @escaping () -> Void,
        popoverPresenter: MetricsPopoverPresenter
    ) {
        self.appState = appState
        self.openSettings = openSettings
        self.popoverPresenter = popoverPresenter
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
        startMouseMonitor()
        panel.orderFrontRegardless()
        syncPopoverAnchorFrame()
    }

    func close() {
        stopMouseMonitor()
        pendingSingleClickTask?.cancel()
        pendingSingleClickTask = nil
        popoverPresenter.close()
        guard let panel else { return }
        savePlacement(for: panel)
        panel.delegate = nil
        panel.contentView = nil
        popoverAnchorView = nil
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

        // Keep popover positioning independent from SwiftUI's coordinate system.
        let anchorView = FloatingPopoverAnchorView(frame: hostingView.bounds)
        anchorView.autoresizingMask = [.width, .height]
        anchorView.setAccessibilityElement(false)
        hostingView.addSubview(anchorView, positioned: .below, relativeTo: nil)
        popoverAnchorView = anchorView
        syncPopoverAnchorFrame()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        savePlacement(for: panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        syncPopoverAnchorFrame()
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

    // MARK: - Click handling

    private func startMouseMonitor() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseEvent(event)
            }
            return event
        }
    }

    private func stopMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        mouseDownLocation = nil
        didDragSinceMouseDown = false
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard let panel, event.window === panel else { return }

        switch event.type {
        case .leftMouseDown:
            pendingSingleClickTask?.cancel()
            pendingSingleClickTask = nil
            mouseDownLocation = NSEvent.mouseLocation
            didDragSinceMouseDown = false

        case .leftMouseDragged:
            guard let mouseDownLocation else { return }
            didDragSinceMouseDown = didDragSinceMouseDown
                || distance(from: mouseDownLocation, to: NSEvent.mouseLocation) > Self.clickMovementTolerance

        case .leftMouseUp:
            guard let mouseDownLocation else { return }
            let isClick = !didDragSinceMouseDown
                && distance(from: mouseDownLocation, to: NSEvent.mouseLocation) <= Self.clickMovementTolerance
            self.mouseDownLocation = nil
            didDragSinceMouseDown = false
            guard isClick else { return }

            if event.clickCount >= 2 {
                pendingSingleClickTask?.cancel()
                pendingSingleClickTask = nil
                popoverPresenter.close()
                openSettings()
            } else {
                scheduleSingleClick(for: panel)
            }

        default:
            break
        }
    }

    private func scheduleSingleClick(for panel: NSPanel) {
        pendingSingleClickTask?.cancel()
        pendingSingleClickTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, let panel, !Task.isCancelled else { return }
            self.pendingSingleClickTask = nil
            guard let anchor = self.popoverAnchorView, panel.isVisible else { return }
            let popoverAnchor = self.popoverAnchor(for: panel, in: anchor)
            self.popoverPresenter.toggle(
                anchor: anchor,
                positioningRect: popoverAnchor.rect,
                preferredEdge: popoverAnchor.edge,
                adjustFrame: { [weak self, weak panel] window in
                    guard let self, let panel else { return }
                    self.adjustPopoverFrame(
                        window,
                        relativeTo: panel,
                        showsBelow: popoverAnchor.showsBelow
                    )
                }
            )
        }
    }

    private func popoverAnchor(for panel: NSPanel, in view: NSView) -> (rect: NSRect, edge: NSRectEdge, showsBelow: Bool) {
        let screen = panel.screen
            ?? NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) }
            ?? NSScreen.main
        guard let screen else { return (view.bounds, .minY, true) }

        let visibleFrame = screen.visibleFrame
        let spaceAbove = max(visibleFrame.maxY - panel.frame.maxY, 0)
        let spaceBelow = max(panel.frame.minY - visibleFrame.minY, 0)
        let showBelow = spaceBelow >= spaceAbove

        // Use a narrow anchor on the outer edge. Anchoring to the full content
        // view lets AppKit center the popover over the panel and cover it.
        let bounds = view.bounds
        let anchorWidth = min(max(bounds.width * 0.5, 1), 8)
        let anchorHeight: CGFloat = 1
        let anchorX = bounds.midX - anchorWidth / 2

        if showBelow {
            return (
                NSRect(
                    x: anchorX,
                    y: bounds.minY,
                    width: anchorWidth,
                    height: anchorHeight
                ),
                .minY,
                true
            )
        }
        return (
            NSRect(
                x: anchorX,
                y: bounds.maxY - anchorHeight,
                width: anchorWidth,
                height: anchorHeight
            ),
            .maxY,
            false
        )
    }

    private func distance(from lhs: NSPoint, to rhs: NSPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func syncPopoverAnchorFrame() {
        guard let panel, let contentView = panel.contentView, let anchorView = popoverAnchorView else { return }
        contentView.layoutSubtreeIfNeeded()
        anchorView.frame = contentView.bounds
    }

    private func adjustPopoverFrame(
        _ window: NSWindow,
        relativeTo panel: NSPanel,
        showsBelow: Bool
    ) {
        guard let screen = panel.screen
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
            ?? NSScreen.main else { return }

        let gap: CGFloat = 4
        var frame = window.frame
        let targetY: CGFloat
        if showsBelow {
            targetY = panel.frame.minY - gap - frame.height
        } else {
            targetY = panel.frame.maxY + gap
        }

        let visibleFrame = screen.visibleFrame
        guard targetY >= visibleFrame.minY,
              targetY + frame.height <= visibleFrame.maxY else { return }

        guard abs(frame.minY - targetY) > 0.5 else { return }
        frame.origin.y = targetY
        window.setFrame(frame, display: true)
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

/// A transparent, non-interactive anchor with a predictable coordinate system.
private final class FloatingPopoverAnchorView: NSView {
    override var isFlipped: Bool { false }
}

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
        let hostingView = DraggableHostingView(
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
            } else if popoverPresenter.isShown {
                // Popover is currently open and survived the click → close it immediately.
                // (The floating path anchors with `.semitransient`, so the click on the
                // floater does NOT auto-dismiss before this handler runs.)
                pendingSingleClickTask?.cancel()
                pendingSingleClickTask = nil
                popoverPresenter.close()
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
        let visibleFrame = screen.visibleFrame

        // MARK: - Vertical
        // 下方：pop 顶边贴在浮窗底边之上（pop 底 = 浮窗底 - gap - 高）
        let belowMinY = panel.frame.minY - gap - frame.height
        // 上方：pop 底边贴在浮窗顶边之上
        let aboveMinY = panel.frame.maxY + gap

        var targetY = showsBelow ? belowMinY : aboveMinY
        func fits(_ y: CGFloat) -> Bool {
            y >= visibleFrame.minY && y + frame.height <= visibleFrame.maxY
        }
        if !fits(targetY) {
            let alternate = showsBelow ? aboveMinY : belowMinY
            targetY = fits(alternate) ? alternate : max(visibleFrame.minY, min(targetY, visibleFrame.maxY - frame.height))
        }

        // MARK: - Horizontal positioning
        // 理想为与浮窗水平中心对齐；当浮窗贴近某侧屏幕边缘导致居中溢出时，
        // 把 pop 贴到浮窗的外侧边缘，而不是让它被 AppKit 夹回屏幕中央而与浮窗错位。
        let w = frame.width
        let maxMinX = visibleFrame.maxX - w
        var targetX = panel.frame.midX - w / 2
        if targetX < visibleFrame.minX {
            targetX = max(visibleFrame.minX, panel.frame.minX)
        } else if targetX > maxMinX {
            targetX = min(maxMinX, panel.frame.maxX - w)
        }

        guard abs(frame.minX - targetX) > 0.5 || abs(frame.minY - targetY) > 0.5 else { return }
        frame.origin.x = targetX
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
        let selectedItems = FloatingMetricsSelection.displayedItems(
            stored: Defaults[.floatingWindowMetricItems],
            monitored: Defaults[.metricMonitorItems]
        )
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

/// A hosting view that hands left-mouse drags over to the window (`performDrag`).
///
/// The floater is a borderless, non-activating panel whose content is SwiftUI, and it used to
/// rely purely on `NSPanel.isMovableByWindowBackground`. Starting with macOS 27 the SwiftUI
/// hosting view consumes the mouse-down itself (for its own gesture pipeline), so AppKit never
/// enters its background-drag session and the floater can no longer be dragged.
///
/// Evidence (probe on macOS 27 with a borderless + `.nonactivatingPanel` window,
/// `isMovableByWindowBackground = true`, driven by real HID events):
///   - contentView = plain `NSView` → window moves (the AppKit path itself is fine);
///   - contentView = `NSHostingView` → window does NOT move, and the mouse-down is already
///     claimed before AppKit's drag path runs;
///   - overriding only `mouseDownCanMoveWindow` to return `true` on the hosting view is NOT
///     enough — 100% of a real drag produces 0px of movement;
///   - overriding `mouseDown` to call `window?.performDrag(with:)` moves the window again.
///
/// Control-click is passed through to SwiftUI so `.contextMenu` keeps working.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }
}

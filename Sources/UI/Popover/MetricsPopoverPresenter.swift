import AppKit
import SwiftUI

/// Presents the metrics popover from any AppKit view.
///
/// The status bar and floating window share this presenter so they always
/// render the same PopoverMetricsView and use the same lifecycle behavior.
@MainActor
final class MetricsPopoverPresenter: NSObject, NSPopoverDelegate {
    private let systemMonitor: SystemMonitor
    private let updateEnabledMetrics: () -> Void
    private let openMainWindow: () -> Void

    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.contentSize = NSSize(width: 336, height: 520)
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        return p
    }()

    /// Global mouse-move monitor for auto-hiding popover when mouse leaves.
    private var globalMouseMonitor: Any?
    private var autoHideTask: Task<Void, Never>?
    /// Kept for the whole time the popover is shown so the anchored edge can be re-pinned
    /// every time the popover window resizes (e.g. expanding a disclosure row). The floating
    /// path pins the edge at the floater, so growth must push AWAY from it — never into it.
    private var adjustFrameHandler: ((NSWindow) -> Void)?
    private var popoverWindowResizeObserver: NSObjectProtocol?
    /// The window that anchors this popover (floating floater, or status bar's window).
    /// Used so the auto-hide does NOT fire while the mouse is over the anchor — hovering
    /// the floater (to click and toggle) must not be treated as "left the popover".
    /// Only applies to the floating path (`positioningRect != nil`); the status bar keeps
    /// its original hide-when-mouse-leaves behavior.
    private weak var anchorWindow: NSWindow?
    private var usesFloatingAnchor = false

    init(
        systemMonitor: SystemMonitor,
        updateEnabledMetrics: @escaping () -> Void,
        openMainWindow: @escaping () -> Void
    ) {
        self.systemMonitor = systemMonitor
        self.updateEnabledMetrics = updateEnabledMetrics
        self.openMainWindow = openMainWindow
        super.init()
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle(
        anchor: NSView,
        positioningRect: NSRect? = nil,
        preferredEdge: NSRectEdge = .minY,
        adjustFrame: ((NSWindow) -> Void)? = nil
    ) {
        self.anchorWindow = anchor.window
        self.usesFloatingAnchor = (positioningRect != nil)
        // The floating floater is a non-activating panel: `.transient` NSPopover auto-dismisses
        // on the very mouseDown that is meant to CLOSE it (a click on the floater itself is an
        // "outside click" for the popover), so `isShown` is already false by the time our mouse-
        // up handler runs → toggle re-opens instead of closing. `.semitransient` only dismisses
        // on app deactivation (not on an outside click), so clicking the floater keeps the popover
        // shown and the ordinary "close on second click" path fires correctly.
        // The status bar path keeps `.transient` (its known-good outside-click dismissal).
        popover.behavior = (positioningRect == nil) ? .transient : .semitransient
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        updateEnabledMetrics()
        // Create fresh content each time to avoid holding the SwiftUI tree in memory.
        popover.contentViewController = NSHostingController(
            rootView: PopoverMetricsView(
                systemMonitor: systemMonitor,
                openMainWindow: { [weak self] in
                    self?.openMainWindowFromPopover()
                }
            )
        )
        adjustFrameHandler = adjustFrame

        // Floating path anchors via a narrow 1px positioningRect on the panel's
        // outer edge. On macOS 26 AppKit's reveal animation for such an off-center
        // anchor grows the popover from the WRONG edge (bottom-up, overshooting the
        // panel) and then adjustFrame snaps it up — visually "从下方闪一下再到位".
        // Disable the reveal animation for this path so before the first draw it is
        // already pinned by adjustFrame in popoverDidShow → no flash, no jump.
        // The status bar (no positioningRect) keeps its normal centered animation.
        popover.animates = (positioningRect == nil)

        popover.show(
            relativeTo: positioningRect ?? anchor.bounds,
            of: anchor,
            preferredEdge: preferredEdge
        )
    }

    func close() {
        if popover.isShown {
            popover.performClose(nil)
        } else if popover.contentViewController != nil {
            // A failed or interrupted presentation can leave content behind without a visible popover.
            stopMouseExitMonitor()
            tearDownAdjustFrameHandler()
            popover.contentViewController = nil
            updateEnabledMetrics()
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        if let window = popover.contentViewController?.view.window,
           let adjustFrame = adjustFrameHandler {
            adjustFrame(window)
        }
        startPopoverWindowResizeObserver()
        startMouseExitMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        stopMouseExitMonitor()
        tearDownAdjustFrameHandler()
        // Release the SwiftUI view tree to free process-monitor subscriptions and memory.
        popover.contentViewController = nil
        updateEnabledMetrics()
    }

    private func openMainWindowFromPopover() {
        popover.performClose(nil)
        openMainWindow()
    }

    // MARK: - Re-pin on resize

    /// On the floating path, the popover window can grow when a disclosure row is expanded.
    /// AppKit grows the window relative to its current top-left, which for an upward-opening
    /// popover pushes the BOTTOM edge down INTO the floater. Re-running the frame handler on
    /// every resize re-pins the anchored edge at the floater so the growth pushes AWAY from it.
    private func startPopoverWindowResizeObserver() {
        stopPopoverWindowResizeObserver()
        guard let window = popover.contentViewController?.view.window else { return }
        popoverWindowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.popover.contentViewController?.view.window else { return }
                self.adjustFrameHandler?(window)
            }
        }
    }

    private func stopPopoverWindowResizeObserver() {
        if let observer = popoverWindowResizeObserver {
            NotificationCenter.default.removeObserver(observer)
            popoverWindowResizeObserver = nil
        }
    }

    private func tearDownAdjustFrameHandler() {
        stopPopoverWindowResizeObserver()
        adjustFrameHandler = nil
    }

    // MARK: - Mouse Exit Auto-Hide

    private func startMouseExitMonitor() {
        stopMouseExitMonitor()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleGlobalMouseMoved()
            }
        }
    }

    private func stopMouseExitMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func handleGlobalMouseMoved() {
        guard popover.isShown else { return }
        guard let window = popover.contentViewController?.view.window else { return }

        let mouseLoc = NSEvent.mouseLocation
        let popoverFrame = window.frame
        // Give a small margin so a user can comfortably interact with popover edges.
        let expandedFrame = popoverFrame.insetBy(dx: -4, dy: -4)
        // The anchor (floating floater / status button) is part of the interaction zone:
        // the popover is shown because the user is clicking/pinned to it, so hovering the
        // anchor to toggle it must NOT count as "mouse left the popover" and auto-close.
        if usesFloatingAnchor, let anchorWin = anchorWindow, anchorWin.isVisible {
            let anchorFrame = anchorWin.frame.insetBy(dx: -6, dy: -6)
            if anchorFrame.contains(mouseLoc) {
                // On the anchor — cancel any pending close.
                autoHideTask?.cancel()
                autoHideTask = nil
                return
            }
        }

        if !expandedFrame.contains(mouseLoc) {
            autoHideTask?.cancel()
            autoHideTask = Task { [weak self, weak anchorWindow] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                // Re-check before actually closing.
                guard let window = self.popover.contentViewController?.view.window else { return }
                let loc = NSEvent.mouseLocation
                // Also keep open if the mouse has moved back over the anchor.
                let overAnchor = self.usesFloatingAnchor
                    && anchorWindow?.isVisible == true
                    && anchorWindow!.frame.insetBy(dx: -6, dy: -6).contains(loc)
                if !window.frame.insetBy(dx: -4, dy: -4).contains(loc) && !overAnchor {
                    self.popover.performClose(nil)
                }
            }
        } else {
            // Mouse is back inside — cancel any pending close.
            autoHideTask?.cancel()
            autoHideTask = nil
        }
    }
}

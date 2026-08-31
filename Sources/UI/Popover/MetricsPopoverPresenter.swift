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
    private var pendingFrameAdjustment: ((NSWindow) -> Void)?

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
        pendingFrameAdjustment = adjustFrame
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
            popover.contentViewController = nil
            pendingFrameAdjustment = nil
            updateEnabledMetrics()
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        if let window = popover.contentViewController?.view.window,
           let adjustFrame = pendingFrameAdjustment {
            adjustFrame(window)
        }
        pendingFrameAdjustment = nil
        startMouseExitMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        stopMouseExitMonitor()
        // Release the SwiftUI view tree to free process-monitor subscriptions and memory.
        popover.contentViewController = nil
        pendingFrameAdjustment = nil
        updateEnabledMetrics()
    }

    private func openMainWindowFromPopover() {
        popover.performClose(nil)
        openMainWindow()
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
        // Give a small margin so the user can comfortably interact with the popover edges.
        let expandedFrame = popoverFrame.insetBy(dx: -4, dy: -4)

        if !expandedFrame.contains(mouseLoc) {
            autoHideTask?.cancel()
            autoHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                // Re-check before actually closing.
                guard let window = self.popover.contentViewController?.view.window else { return }
                let loc = NSEvent.mouseLocation
                if !window.frame.insetBy(dx: -4, dy: -4).contains(loc) {
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

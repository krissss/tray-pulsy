import AppKit
import SwiftUI
import XCTest
@testable import TrayPulsy

@MainActor
final class FloatingSkinFrameViewTests: XCTestCase {
    func testLegacyLargeFrameDoesNotOverflowSwiftUIContainer() {
        let skinSize = FloatingMetricsLayoutMetrics.skinSize
        let frameView = FloatingSkinFrameView()
        frameView.setFrameImage(NSImage(size: NSSize(width: 98, height: 98)))

        let hostingView = NSHostingView(
            rootView: FloatingSkinFrameRepresentable(frameView: frameView)
                .frame(width: skinSize, height: skinSize)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: skinSize, height: skinSize)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(frameView.intrinsicContentSize, NSSize(width: skinSize, height: skinSize))
        XCTAssertEqual(frameView.frame.size, NSSize(width: skinSize, height: skinSize))
        XCTAssertEqual(frameView.bounds.size, NSSize(width: skinSize, height: skinSize))
        XCTAssertEqual(frameView.layer?.masksToBounds, true)
    }
}

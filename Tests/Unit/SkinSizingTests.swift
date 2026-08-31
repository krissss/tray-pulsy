import CoreGraphics
import XCTest
@testable import TrayPulsy

final class SkinSizingTests: XCTestCase {
    func testLegacyMarioCanvasUsesFullDisplayBox() {
        let size = SkinSizing.displaySize(
            source: CGSize(width: 98, height: 98),
            box: CGSize(width: 22, height: 22)
        )

        XCTAssertEqual(size.width, 22, accuracy: 0.001)
        XCTAssertEqual(size.height, 22, accuracy: 0.001)
    }

    func testLargeNonSquareSpriteKeepsAspectRatioAtFullFill() {
        let source = CGSize(width: 98, height: 64)
        let size = SkinSizing.displaySize(source: source, box: CGSize(width: 22, height: 22))

        XCTAssertEqual(size.width, 22, accuracy: 0.001)
        XCTAssertEqual(size.width / size.height, source.width / source.height, accuracy: 0.001)
    }
}

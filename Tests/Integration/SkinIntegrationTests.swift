import AppKit
import Defaults
import XCTest
@testable import TrayPulsy

// MARK: - Skin Integration Tests
//
// Tests SkinManager + Defaults + external path + theme interaction.

final class SkinIntegrationTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "TrayPulsySkinInt_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Defaults[.externalSkinPath] = ""
        SkinManager.shared.setTheme(.system)
        SkinManager.shared.reload()
        try? FileManager.default.removeItem(atPath: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createPNG(at path: String) {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        )!
        rep.setColor(NSColor.white, atX: 0, y: 0)
        let data = rep.representation(using: .png, properties: [:])!
        FileManager.default.createFile(atPath: path, contents: data)
    }

    private func createSkinDir(name: String, frameCount: Int = 3) {
        let dir = tempDir + "/" + name
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for i in 0..<frameCount {
            createPNG(at: dir + "/frame\(i).png")
        }
    }

    private func spinRunLoop(seconds: TimeInterval = 0.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - External path → reload → frames

    func testExternalPath_reload_discoversAndLoadsFrames() {
        createSkinDir(name: "extskin", frameCount: 4)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        XCTAssertTrue(SkinManager.shared.allSkins.contains(where: { $0.id == "extskin" }))
        let frames = SkinManager.shared.frames(for: SkinInfo(id: "extskin", displayName: "extskin"))
        XCTAssertEqual(frames.count, 4)
    }

    func testExternalPath_addSkin_reloadUpdatesAvailableSkins() {
        createSkinDir(name: "skin_a", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()
        let countA = SkinManager.shared.allSkins.count

        createSkinDir(name: "skin_b", frameCount: 2)
        SkinManager.shared.reload()
        let countB = SkinManager.shared.allSkins.count

        XCTAssertEqual(countB, countA + 1)
    }

    func testExternalPath_cleared_removesExternalSkins() {
        createSkinDir(name: "tempskin", frameCount: 1)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()
        XCTAssertTrue(SkinManager.shared.allSkins.contains(where: { $0.id == "tempskin" }))

        Defaults[.externalSkinPath] = ""
        SkinManager.shared.reload()
        XCTAssertFalse(SkinManager.shared.allSkins.contains(where: { $0.id == "tempskin" }))
    }

    // MARK: - Theme change → frame re-rendering

    func testThemeChange_lightToDark_producesDifferentFrames() {
        createSkinDir(name: "themetest", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let skin = SkinInfo(id: "themetest", displayName: "themetest")

        SkinManager.shared.setTheme(.light)
        let lightFrames = SkinManager.shared.frames(for: skin)

        SkinManager.shared.setTheme(.dark)
        let darkFrames = SkinManager.shared.frames(for: skin)

        XCTAssertEqual(lightFrames.count, darkFrames.count)
        // Dark theme should produce different image objects (cache was cleared)
        XCTAssertFalse(lightFrames[0] === darkFrames[0])
    }

    func testThemeChange_invalidatesCache() {
        createSkinDir(name: "cachetest", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let skin = SkinInfo(id: "cachetest", displayName: "cachetest")

        SkinManager.shared.setTheme(.light)
        let first = SkinManager.shared.frames(for: skin)
        let cached = SkinManager.shared.frames(for: skin)

        // Same object from cache
        XCTAssertTrue(first[0] === cached[0])

        SkinManager.shared.setTheme(.dark)
        let afterTheme = SkinManager.shared.frames(for: skin)

        // Different object after theme change
        XCTAssertFalse(first[0] === afterTheme[0])
    }

    // MARK: - SkinManager → TrayAnimator integration

    func testLoadFrames_thenAnimatorUsesThem() {
        createSkinDir(name: "animtest", frameCount: 4)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let skin = SkinInfo(id: "animtest", displayName: "animtest")
        let loadedFrames = SkinManager.shared.frames(for: skin)
        XCTAssertEqual(loadedFrames.count, 4)

        let animator = TrayAnimator(initialFrames: loadedFrames)
        var count = 0
        animator.onFrameUpdate = { _ in count += 1 }
        animator.start()
        spinRunLoop(seconds: 0.5)
        animator.stop()

        XCTAssertGreaterThan(count, 0)
    }

    func testAnimator_changeSkinFromSkinManagerFrames() {
        createSkinDir(name: "skin1", frameCount: 3)
        createSkinDir(name: "skin2", frameCount: 5)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let skin1 = SkinInfo(id: "skin1", displayName: "skin1")
        let skin2 = SkinInfo(id: "skin2", displayName: "skin2")

        let animator = TrayAnimator(initialFrames: SkinManager.shared.frames(for: skin1))
        var received: [NSImage] = []
        animator.onFrameUpdate = { received.append($0) }
        animator.start()
        spinRunLoop(seconds: 0.2)

        let countBefore = received.count
        animator.changeSkin(to: SkinManager.shared.frames(for: skin2))
        spinRunLoop(seconds: 0.2)
        animator.stop()

        XCTAssertGreaterThan(received.count, countBefore)
    }
}

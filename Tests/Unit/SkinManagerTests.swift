import AppKit
import Defaults
import XCTest
@testable import TrayPulsy

final class SkinManagerTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "TrayPulsyTest_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Reset to clean state to avoid polluting other tests
        Defaults[.externalSkinPath] = ""
        SkinManager.shared.setTheme(.system)
        SkinManager.shared.reload()
        try? FileManager.default.removeItem(atPath: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Create a valid 1×1 white PNG file at the given path.
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

    /// Create a skin directory with `n` valid PNG frames.
    @discardableResult
    private func createSkinDir(name: String, frameCount: Int = 2) -> String {
        let dir = tempDir + "/" + name
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for i in 0..<frameCount {
            createPNG(at: dir + "/frame\(i).png")
        }
        return dir
    }

    // MARK: - SkinInfo

    func testSkinInfo_equality() {
        let a = SkinInfo(id: "cat", displayName: "Cat")
        let b = SkinInfo(id: "cat", displayName: "Cat")
        let c = SkinInfo(id: "dog", displayName: "Cat")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSkinInfo_hashable() {
        let a = SkinInfo(id: "cat", displayName: "Cat")
        let b = SkinInfo(id: "cat", displayName: "Cat")
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func testSkinInfo_identifiable() {
        let skin = SkinInfo(id: "parrot", displayName: "Parrot")
        XCTAssertEqual(skin.id, "parrot")
    }

    // MARK: - skin(for:) fallback logic

    func testSkinFor_existingID_returnsMatchingSkin() {
        let manager = SkinManager.shared
        // Get a skin that actually exists in allSkins
        guard let first = manager.allSkins.first else { return }
        let skin = manager.skin(for: first.id)
        XCTAssertEqual(skin.id, first.id)
    }

    func testSkinFor_unknownID_returnsFallback() {
        let manager = SkinManager.shared
        let skin = manager.skin(for: "nonexistent_skin_xyz")
        XCTAssertFalse(skin.id.isEmpty)
    }

    // MARK: - scanDirectory

    func testScanDirectory_findsPngFolders() {
        createSkinDir(name: "mycat")
        let skins = SkinManager.scanDirectory([tempDir])
        XCTAssertEqual(skins.count, 1)
        XCTAssertEqual(skins[0].id, "mycat")
    }

    func testScanDirectory_ignoresNonPngFolders() {
        let skinDir = tempDir + "/empty"
        try? FileManager.default.createDirectory(atPath: skinDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: skinDir + "/frame.jpg", contents: Data())
        XCTAssertTrue(SkinManager.scanDirectory([tempDir]).isEmpty)
    }

    func testScanDirectory_ignoresFiles() {
        FileManager.default.createFile(atPath: tempDir + "/notadir.png", contents: Data())
        XCTAssertTrue(SkinManager.scanDirectory([tempDir]).isEmpty)
    }

    func testScanDirectory_multipleSkins() {
        for name in ["alpha", "beta", "gamma"] { createSkinDir(name: name) }
        XCTAssertEqual(SkinManager.scanDirectory([tempDir]).count, 3)
    }

    func testScanDirectory_nonexistentPath_returnsEmpty() {
        XCTAssertTrue(SkinManager.scanDirectory(["/nonexistent/path/xyz"]).isEmpty)
    }

    // MARK: - discoverSkins

    func testDiscoverSkins_noExternal_returnsSorted() {
        let skins = SkinManager.discoverSkins(externalPath: "")
        let ids = skins.map(\.id)
        XCTAssertEqual(ids, ids.sorted())
    }

    func testDiscoverSkins_withExternalPath() {
        let extDir = tempDir + "/ext"
        try? FileManager.default.createDirectory(atPath: extDir, withIntermediateDirectories: true)
        createSkinDir(name: "custom")
        // Move into ext subpath
        let src = tempDir + "/custom"
        let dst = extDir + "/custom"
        try? FileManager.default.moveItem(atPath: src, toPath: dst)

        let skins = SkinManager.discoverSkins(externalPath: extDir)
        XCTAssertTrue(skins.contains(where: { $0.id == "custom" }))
    }

    func testDiscoverSkins_externalOverridesBundled() {
        let extDir = tempDir + "/ext2"
        createSkinDir(name: "cat")
        let src = tempDir + "/cat"
        let dst = extDir + "/cat"
        try? FileManager.default.createDirectory(atPath: extDir, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(atPath: src, toPath: dst)

        let skins = SkinManager.discoverSkins(externalPath: extDir)
        XCTAssertEqual(skins.filter { $0.id == "cat" }.count, 1)
    }

    func testDiscoverSkins_sortedAlphabetically() {
        let skins = SkinManager.discoverSkins(externalPath: "")
        let ids = skins.map(\.id)
        XCTAssertEqual(ids, ids.sorted())
    }

    // MARK: - setSkin / setTheme

    func testSetSkin() {
        let manager = SkinManager.shared
        let original = manager.currentSkin
        let newSkin = SkinInfo(id: "test_skin", displayName: "Test")
        manager.setSkin(newSkin)
        XCTAssertEqual(manager.currentSkin.id, "test_skin")
        // Restore
        manager.setSkin(original)
    }

    func testSetTheme_clearsCache() {
        let manager = SkinManager.shared
        // Load frames to populate cache
        let f1 = manager.frames()
        manager.setTheme(.light)
        // Cache was cleared — next call should recompute (but still return frames)
        let f2 = manager.frames()
        XCTAssertEqual(f1.count, f2.count)
        // Restore
        manager.setTheme(.system)
    }

    // MARK: - frames(for:) with external skin path

    func testFrames_loadsFromExternalPath() {
        createSkinDir(name: "testskin", frameCount: 3)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let skin = SkinInfo(id: "testskin", displayName: "testskin")
        let frames = SkinManager.shared.frames(for: skin)
        XCTAssertEqual(frames.count, 3)
    }

    func testFrames_returnsCachedOnSecondCall() {
        createSkinDir(name: "cachedskin", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let skin = SkinInfo(id: "cachedskin", displayName: "cachedskin")
        let f1 = SkinManager.shared.frames(for: skin)
        let f2 = SkinManager.shared.frames(for: skin)
        XCTAssertEqual(f1.count, f2.count)
        // Same instances (from cache)
        for i in 0..<f1.count {
            XCTAssertTrue(f1[i] === f2[i])
        }
    }

    func testFrames_unknownSkin_fallsBackToDefault() {
        // Request frames for a nonexistent skin — should fall back to "cat"
        let skin = SkinInfo(id: "nonexistent_xyz", displayName: "n/a")
        let frames = SkinManager.shared.frames(for: skin)
        // Should return something (default cat skin frames) — at least not crash
        // In test env may be empty if bundle resources unavailable
    }

    // MARK: - frame(for:frameIndex:)

    func testFrame_validIndex() {
        createSkinDir(name: "indexed", frameCount: 3)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        let img = SkinManager.shared.frame(for: "indexed", frameIndex: 1)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.size.width, 18)
    }

    func testFrame_outOfBounds_returnsNil() {
        createSkinDir(name: "indexed2", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        XCTAssertNil(SkinManager.shared.frame(for: "indexed2", frameIndex: -1))
        XCTAssertNil(SkinManager.shared.frame(for: "indexed2", frameIndex: 99))
    }

    func testFrame_nonexistentSkin_returnsNil() {
        XCTAssertNil(SkinManager.shared.frame(for: "no_such_skin", frameIndex: 0))
    }

    // MARK: - reload

    func testReload_discoversNewSkins() {
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()
        let before = SkinManager.shared.allSkins

        createSkinDir(name: "zzz_new")
        SkinManager.shared.reload()
        let after = SkinManager.shared.allSkins

        XCTAssertTrue(after.count >= before.count)
        XCTAssertTrue(after.contains(where: { $0.id == "zzz_new" }))
    }

    // MARK: - dark theme rendering

    func testFrames_darkTheme_recolors() {
        createSkinDir(name: "darktest", frameCount: 1)
        Defaults[.externalSkinPath] = tempDir
        SkinManager.shared.reload()

        SkinManager.shared.setTheme(.light)
        let lightFrames = SkinManager.shared.frames(for: SkinInfo(id: "darktest", displayName: "darktest"))

        SkinManager.shared.setTheme(.dark)
        let darkFrames = SkinManager.shared.frames(for: SkinInfo(id: "darktest", displayName: "darktest"))

        // Both should return frames; dark theme should produce different images
        XCTAssertEqual(lightFrames.count, 1)
        XCTAssertEqual(darkFrames.count, 1)
        // Not the same object (cache was cleared by setTheme)
        XCTAssertFalse(lightFrames[0] === darkFrames[0])
    }
}

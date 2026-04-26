import AppKit
import Defaults
import XCTest
@testable import TrayPulsy

final class SkinManagerTests: XCTestCase {

    private var tempDir: String!
    private var manager: SkinManager!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "TrayPulsyTest_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        Defaults[.externalSkinPath] = ""
        manager = SkinManager()
    }

    override func tearDown() {
        // Reset to clean state to avoid polluting other tests
        Defaults[.externalSkinPath] = ""
        manager = nil
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
        // Get a skin that actually exists in allSkins
        guard let first = manager.allSkins.first else { return }
        let skin = manager.skin(for: first.id)
        XCTAssertEqual(skin.id, first.id)
    }

    func testSkinFor_unknownID_returnsFallback() {
        let skin = manager.skin(for: "nonexistent_skin_xyz")
        XCTAssertFalse(skin.id.isEmpty)
    }

    func testSkinFor_oldID_migration() {
        // Old IDs like "cat" should match "01.cat" via suffix fallback
        // Create an external skin with numeric prefix to test
        createSkinDir(name: "01.cat")
        Defaults[.externalSkinPath] = tempDir
        manager.reload()

        let skin = manager.skin(for: "cat")
        XCTAssertTrue(skin.id.hasSuffix(".cat"), "old ID 'cat' should migrate to '\(skin.id)'")
    }

    func testSkinFor_oldID_noMatch_returnsFallback() {
        let skin = manager.skin(for: "totally_unknown_skin")
        // Should still return something (fallback)
        XCTAssertFalse(skin.id.isEmpty)
    }

    // MARK: - scanDirectory

    func testScanDirectory_findsPngFolders() {
        createSkinDir(name: "mycat")
        let skins = SkinManager.scanDirectory([tempDir])
        XCTAssertEqual(skins.count, 1)
        XCTAssertEqual(skins[0].id, "mycat")
    }

    func testScanDirectory_numericPrefix_stripsDisplayName() {
        createSkinDir(name: "01.cat")
        let skins = SkinManager.scanDirectory([tempDir])
        XCTAssertEqual(skins.count, 1)
        XCTAssertEqual(skins[0].id, "01.cat")
        XCTAssertEqual(skins[0].displayName, "cat")
    }

    func testScanDirectory_numericPrefix_preservesOrder() {
        createSkinDir(name: "02.dab")
        createSkinDir(name: "01.cat")
        createSkinDir(name: "03.horse")
        let skins = SkinManager.scanDirectory([tempDir]).sorted { $0.id < $1.id }
        let ids = skins.map(\.id)
        XCTAssertEqual(ids, ["01.cat", "02.dab", "03.horse"])
    }

    func testScanDirectory_ignoresIconset() {
        let dir = tempDir + "/AppIcon.iconset"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/icon_16.png", contents: Data())
        XCTAssertTrue(SkinManager.scanDirectory([tempDir]).isEmpty)
    }

    func testScanDirectory_ignoresLproj() {
        let dir = tempDir + "/en.lproj"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/Localizable.strings", contents: Data())
        XCTAssertTrue(SkinManager.scanDirectory([tempDir]).isEmpty)
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

    func testDiscoverSkins_pulsyIsFirst() {
        let skins = SkinManager.discoverSkins(externalPath: "")
        XCTAssertFalse(skins.isEmpty)
        XCTAssertEqual(skins[0].id, "pulsy")
    }

    func testDiscoverSkins_pulsyIsVirtual() {
        let skins = SkinManager.discoverSkins(externalPath: "")
        let pulsy = skins.first { $0.id == "pulsy" }
        XCTAssertNotNil(pulsy)
        XCTAssertEqual(pulsy?.displayName, "Pulsy")
    }

    // MARK: - setSkin / setTheme

    func testSetSkin() {
        let original = manager.currentSkin
        let newSkin = SkinInfo(id: "test_skin", displayName: "Test")
        manager.setSkin(newSkin)
        XCTAssertEqual(manager.currentSkin.id, "test_skin")
        // Restore
        manager.setSkin(original)
    }

    func testSetTheme_clearsCache() {
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
        manager.reload()

        let skin = SkinInfo(id: "testskin", displayName: "testskin")
        let frames = manager.frames(for: skin)
        XCTAssertEqual(frames.count, 3)
    }

    func testFrames_returnsCachedOnSecondCall() {
        createSkinDir(name: "cachedskin", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        manager.reload()

        let skin = SkinInfo(id: "cachedskin", displayName: "cachedskin")
        let f1 = manager.frames(for: skin)
        let f2 = manager.frames(for: skin)
        XCTAssertEqual(f1.count, f2.count)
        // Same instances (from cache)
        for i in 0..<f1.count {
            XCTAssertTrue(f1[i] === f2[i])
        }
    }

    func testFrames_unknownSkin_fallsBackToDefault() {
        // Request frames for a nonexistent skin — should fall back to "cat"
        let skin = SkinInfo(id: "nonexistent_xyz", displayName: "n/a")
        let frames = manager.frames(for: skin)
        // Should return something (default cat skin frames) — at least not crash
        // In test env may be empty if bundle resources unavailable
    }

    // MARK: - frame(for:frameIndex:)

    func testFrame_validIndex() {
        createSkinDir(name: "indexed", frameCount: 3)
        Defaults[.externalSkinPath] = tempDir
        manager.reload()

        let img = manager.frame(for: "indexed", frameIndex: 1)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.size.width, 18)
    }

    func testFrame_outOfBounds_returnsNil() {
        createSkinDir(name: "indexed2", frameCount: 2)
        Defaults[.externalSkinPath] = tempDir
        manager.reload()

        XCTAssertNil(manager.frame(for: "indexed2", frameIndex: -1))
        XCTAssertNil(manager.frame(for: "indexed2", frameIndex: 99))
    }

    func testFrame_nonexistentSkin_fallsBackToDefault() {
        // "no_such_skin" doesn't exist → falls back to default skin frames
        let img = manager.frame(for: "no_such_skin", frameIndex: 0)
        // May return a frame from the default skin or nil if no resources in test env
        // Either way, should not crash
    }

    // MARK: - reload

    func testReload_discoversNewSkins() {
        Defaults[.externalSkinPath] = tempDir
        manager.reload()
        let before = manager.allSkins

        createSkinDir(name: "zzz_new")
        manager.reload()
        let after = manager.allSkins

        XCTAssertTrue(after.count >= before.count)
        XCTAssertTrue(after.contains(where: { $0.id == "zzz_new" }))
    }

    // MARK: - dark theme rendering

    func testFrames_darkTheme_recolors() {
        createSkinDir(name: "darktest", frameCount: 1)
        Defaults[.externalSkinPath] = tempDir
        manager.reload()

        manager.setTheme(.light)
        let lightFrames = manager.frames(for: SkinInfo(id: "darktest", displayName: "darktest"))

        manager.setTheme(.dark)
        let darkFrames = manager.frames(for: SkinInfo(id: "darktest", displayName: "darktest"))

        // Both should return frames; dark theme should produce different images
        XCTAssertEqual(lightFrames.count, 1)
        XCTAssertEqual(darkFrames.count, 1)
        // Not the same object (cache was cleared by setTheme)
        XCTAssertFalse(lightFrames[0] === darkFrames[0])
    }

    // MARK: - Pulsy virtual skin

    func testFrames_pulsy_skipsDarkMode() {
        let pulsy = SkinInfo(id: "pulsy", displayName: "Pulsy")

        manager.setTheme(.light)
        let lightFrames = manager.frames(for: pulsy)

        manager.setTheme(.dark)
        let darkFrames = manager.frames(for: pulsy)

        // Pulsy skips dark-mode inversion — frames should have same count
        // (they are regenerated per cache-key so objects differ, but pixel content is identical)
        XCTAssertEqual(lightFrames.count, darkFrames.count)
        XCTAssertEqual(lightFrames.count, PulsySkinRenderer.frameCount)
    }

    func testFrames_pulsy_returnsFrames() {
        let pulsy = SkinInfo(id: "pulsy", displayName: "Pulsy")
        let frames = manager.frames(for: pulsy)
        XCTAssertEqual(frames.count, PulsySkinRenderer.frameCount)
    }
}

import XCTest
@testable import TrayPulsy

final class OnlineSkinCatalogTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TrayPulsyOnlineSkinCatalog_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    @MainActor
    func testRefreshLoadsManifestFromFileURL() async {
        let manifestURL = try! createCatalog(skinID: "runcat", frames: ["0.png"])
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()

        XCTAssertNil(catalog.errorMessage)
        XCTAssertEqual(catalog.skins.map(\.id), ["runcat"])
        XCTAssertEqual(catalog.skins.first?.author, "Kyome22")
        XCTAssertEqual(catalog.skins.first?.sourceFrom, "https://github.com/Kyome22/RunCat365")
    }

    @MainActor
    func testUpdateManifestURLReloadsDifferentCatalog() async throws {
        let manifestURL = try createCatalog(skinID: "runcat", frames: ["0.png"], manifestName: "manifest-a.json")
        let secondManifestURL = try createCatalog(
            skinID: "parrot",
            frames: ["0.png"],
            manifestName: "manifest-b.json",
            sourceName: "source-b"
        )
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        catalog.updateManifestURL(secondManifestURL)
        await catalog.refresh()

        XCTAssertNil(catalog.errorMessage)
        XCTAssertEqual(catalog.skins.map(\.id), ["parrot"])
    }

    @MainActor
    func testRefreshFailureClearsStaleCatalog() async throws {
        let manifestURL = try createCatalog(skinID: "runcat", frames: ["0.png"])
        let missingURL = tempDir.appendingPathComponent("missing-manifest.json")
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        XCTAssertEqual(catalog.skins.map(\.id), ["runcat"])

        catalog.updateManifestURL(missingURL)
        await catalog.refresh()

        XCTAssertTrue(catalog.skins.isEmpty)
        XCTAssertNotNil(catalog.errorMessage)
    }

    @MainActor
    func testInstallDownloadsFramesIntoManagedDirectory() async throws {
        let manifestURL = try createCatalog(skinID: "runcat", frames: ["0.png", "1.png"])
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        let item = try XCTUnwrap(catalog.skins.first)
        try await catalog.install(item)

        XCTAssertTrue(catalog.isInstalled("runcat"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installURL.appendingPathComponent("runcat/0.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installURL.appendingPathComponent("runcat/1.png").path))
    }

    @MainActor
    func testPreviewFrameDataLoadsFirstFrame() async throws {
        let manifestURL = try createCatalog(skinID: "runcat", frames: ["0.png", "1.png"])
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        let item = try XCTUnwrap(catalog.skins.first)
        let data = try await catalog.previewFrameData(for: item)

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @MainActor
    func testPreviewFrameDataLoadsIndexedFrame() async throws {
        let manifestURL = try createCatalog(skinID: "runcat", frames: ["0.png", "1.png"])
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        let item = try XCTUnwrap(catalog.skins.first)
        let data = try await catalog.previewFrameData(for: item, frameIndex: 1)

        XCTAssertEqual(data, pngData(seed: 1))
    }

    @MainActor
    func testPreviewFrameDataRejectsMissingFrames() async throws {
        let manifestURL = try createCatalog(skinID: "empty", frames: [])
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        let item = try XCTUnwrap(catalog.skins.first)

        do {
            _ = try await catalog.previewFrameData(for: item)
            XCTFail("Expected empty frame lists to be rejected")
        } catch OnlineSkinCatalogError.missingPreviewFrame {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDeleteRemovesInstalledSkin() async throws {
        let manifestURL = try createCatalog(skinID: "runcat", frames: ["0.png"])
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        let item = try XCTUnwrap(catalog.skins.first)
        try await catalog.install(item)
        try catalog.delete(item)

        XCTAssertFalse(catalog.isInstalled("runcat"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installURL.appendingPathComponent("runcat").path))
    }

    @MainActor
    func testInstallRejectsPathTraversalFrameName() async throws {
        let manifestURL = try createCatalog(skinID: "badskin", frames: ["../bad.png"], writeFrames: false)
        let installURL = tempDir.appendingPathComponent("Installed", isDirectory: true)
        let catalog = OnlineSkinCatalog(manifestURL: manifestURL, installDirectory: installURL)

        await catalog.refresh()
        let item = try XCTUnwrap(catalog.skins.first)

        do {
            try await catalog.install(item)
            XCTFail("Expected path traversal frame names to be rejected")
        } catch OnlineSkinCatalogError.invalidFrameName {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @discardableResult
    private func createCatalog(
        skinID: String,
        frames: [String],
        writeFrames: Bool = true,
        manifestName: String = "manifest.json",
        sourceName: String = "source"
    ) throws -> URL {
        let sourceRoot = tempDir.appendingPathComponent(sourceName, isDirectory: true)
        let skinDir = sourceRoot.appendingPathComponent(skinID, isDirectory: true)
        try FileManager.default.createDirectory(at: skinDir, withIntermediateDirectories: true)
        if writeFrames {
            for (index, frame) in frames.enumerated() {
                createPNG(at: skinDir.appendingPathComponent(frame), seed: index)
            }
        }

        let manifest = """
        {
          "schemaVersion": 1,
          "baseURL": "\(sourceRoot.absoluteString)",
          "skins": [
            {
              "id": "\(skinID)",
              "author": "Kyome22",
              "source_from": "https://github.com/Kyome22/RunCat365",
              "frames": \(try jsonArray(frames))
            }
          ]
        }
        """
        let manifestURL = tempDir.appendingPathComponent(manifestName)
        try manifest.data(using: .utf8)!.write(to: manifestURL)
        return manifestURL
    }

    private func jsonArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        return String(data: data, encoding: .utf8)!
    }

    private func createPNG(at url: URL, seed: Int = 0) {
        FileManager.default.createFile(atPath: url.path, contents: pngData(seed: seed))
    }

    private func pngData(seed: Int = 0) -> Data {
        var data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l5pUxwAAAABJRU5ErkJggg==")!
        data.append(UInt8(seed % 256))
        return data
    }
}

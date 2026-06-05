import Foundation
import Observation

struct OnlineSkinCatalogItem: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let author: String
    let sourceFrom: String
    let frames: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case sourceFrom = "source_from"
        case frames
    }
}

struct OnlineSkinManifest: Sendable, Decodable {
    let schemaVersion: Int
    let baseURL: URL
    let skins: [OnlineSkinCatalogItem]
}

enum OnlineSkinCatalogError: LocalizedError {
    case unsupportedSchema(Int)
    case missingBaseURL
    case missingPreviewFrame(String)
    case invalidSkinID(String)
    case invalidFrameName(String)
    case httpStatus(Int)
    case oversizedFrame(String)
    case invalidPNG(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported skin catalog schema: \(version)"
        case .missingBaseURL:
            return "Skin catalog is missing a base URL"
        case .missingPreviewFrame(let id):
            return "Skin has no preview frame: \(id)"
        case .invalidSkinID(let id):
            return "Invalid skin id: \(id)"
        case .invalidFrameName(let name):
            return "Invalid frame name: \(name)"
        case .httpStatus(let code):
            return "Skin catalog request failed with HTTP \(code)"
        case .oversizedFrame(let name):
            return "Skin frame is too large: \(name)"
        case .invalidPNG(let name):
            return "Skin frame is not a PNG: \(name)"
        }
    }
}

@MainActor
@Observable
final class OnlineSkinCatalog {
    nonisolated static let defaultManifestURL = URL(string: "https://raw.githubusercontent.com/krissss/tray-pulsy-skins/main/manifest.json")!
    nonisolated static let maxFrameBytes = 2_000_000

    nonisolated static var defaultInstallDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("TrayPulsy", isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)
    }

    let installDirectory: URL

    private(set) var manifestURL: URL
    private(set) var skins: [OnlineSkinCatalogItem] = []
    private(set) var installedSkinIDs: Set<String> = []
    private(set) var installingSkinIDs: Set<String> = []
    private(set) var isRefreshing = false
    var errorMessage: String?

    private var baseURL: URL?

    init(
        manifestURL: URL = OnlineSkinCatalog.defaultManifestURL,
        installDirectory: URL = OnlineSkinCatalog.defaultInstallDirectory
    ) {
        self.manifestURL = manifestURL
        self.installDirectory = installDirectory
        reloadInstalledSkins()
    }

    func updateManifestURL(_ url: URL) {
        guard manifestURL != url else { return }
        manifestURL = url
        baseURL = nil
        skins = []
        errorMessage = nil
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let manifest = try await Self.fetchManifest(from: manifestURL)
            guard manifest.schemaVersion == 1 else {
                throw OnlineSkinCatalogError.unsupportedSchema(manifest.schemaVersion)
            }
            baseURL = manifest.baseURL
            skins = manifest.skins
            reloadInstalledSkins()
            errorMessage = nil
        } catch {
            baseURL = nil
            skins = []
            errorMessage = error.localizedDescription
        }
    }

    func install(_ skin: OnlineSkinCatalogItem) async throws {
        guard let baseURL else { throw OnlineSkinCatalogError.missingBaseURL }
        installingSkinIDs.insert(skin.id)
        defer {
            installingSkinIDs.remove(skin.id)
            reloadInstalledSkins()
        }

        do {
            try await Self.install(skin, from: baseURL, into: installDirectory)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ skin: OnlineSkinCatalogItem) throws {
        do {
            try Self.validateSkinID(skin.id)
            let target = installDirectory.appendingPathComponent(skin.id, isDirectory: true)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            reloadInstalledSkins()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func isInstalled(_ skinID: String) -> Bool {
        installedSkinIDs.contains(skinID)
    }

    func isInstalling(_ skinID: String) -> Bool {
        installingSkinIDs.contains(skinID)
    }

    func sourceURL(for skin: OnlineSkinCatalogItem) -> URL? {
        URL(string: skin.sourceFrom)
    }

    func previewFrameData(for skin: OnlineSkinCatalogItem) async throws -> Data {
        try await previewFrameData(for: skin, frameIndex: 0)
    }

    func previewFrameData(for skin: OnlineSkinCatalogItem, frameIndex: Int) async throws -> Data {
        guard !skin.frames.isEmpty else {
            throw OnlineSkinCatalogError.missingPreviewFrame(skin.id)
        }
        let index = (frameIndex % skin.frames.count + skin.frames.count) % skin.frames.count
        let frameName = skin.frames[index]
        try Self.validateSkinID(skin.id)
        try Self.validateFrameName(frameName)

        if isInstalled(skin.id) {
            let localURL = installDirectory
                .appendingPathComponent(skin.id, isDirectory: true)
                .appendingPathComponent(frameName)
            if let data = try? Data(contentsOf: localURL),
               data.count <= Self.maxFrameBytes,
               Self.isPNG(data) {
                return data
            }
        }

        guard let baseURL else { throw OnlineSkinCatalogError.missingBaseURL }
        let data = try await Self.fetchData(from: Self.frameURL(for: skin, frameName: frameName, baseURL: baseURL))
        guard data.count <= Self.maxFrameBytes else {
            throw OnlineSkinCatalogError.oversizedFrame(frameName)
        }
        guard Self.isPNG(data) else {
            throw OnlineSkinCatalogError.invalidPNG(frameName)
        }
        return data
    }

    func reloadInstalledSkins() {
        installedSkinIDs = Self.installedSkinIDs(in: installDirectory)
    }

    private nonisolated static func fetchManifest(from url: URL) async throws -> OnlineSkinManifest {
        let data = try await fetchData(from: url)
        return try JSONDecoder().decode(OnlineSkinManifest.self, from: data)
    }

    private nonisolated static func install(
        _ skin: OnlineSkinCatalogItem,
        from baseURL: URL,
        into installDirectory: URL
    ) async throws {
        try validateSkinID(skin.id)
        let frameNames = try skin.frames.map { frame -> String in
            try validateFrameName(frame)
            return frame
        }

        let fm = FileManager.default
        let parent = installDirectory
        let temp = parent.appendingPathComponent(".\(skin.id)-\(UUID().uuidString)", isDirectory: true)
        let target = parent.appendingPathComponent(skin.id, isDirectory: true)

        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            for frame in frameNames {
                let url = frameURL(for: skin, frameName: frame, baseURL: baseURL)
                let data = try await fetchData(from: url)
                guard data.count <= maxFrameBytes else {
                    throw OnlineSkinCatalogError.oversizedFrame(frame)
                }
                guard isPNG(data) else {
                    throw OnlineSkinCatalogError.invalidPNG(frame)
                }
                try data.write(to: temp.appendingPathComponent(frame), options: .atomic)
            }

            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.moveItem(at: temp, to: target)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    private nonisolated static func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw OnlineSkinCatalogError.httpStatus(http.statusCode)
        }
        return data
    }

    private nonisolated static func frameURL(
        for skin: OnlineSkinCatalogItem,
        frameName: String,
        baseURL: URL
    ) -> URL {
        baseURL
            .appendingPathComponent(skin.id, isDirectory: true)
            .appendingPathComponent(frameName)
    }

    private nonisolated static func installedSkinIDs(in directory: URL) -> Set<String> {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let ids = contents.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            guard let frames = try? fm.contentsOfDirectory(atPath: url.path),
                  frames.contains(where: { $0.lowercased().hasSuffix(".png") }) else {
                return nil
            }
            return url.lastPathComponent
        }
        return Set(ids)
    }

    private nonisolated static func validateSkinID(_ id: String) throws {
        let isValid = !id.isEmpty && id.count <= 64 && id.allSatisfy { char in
            char.isASCII && (char.isLetter || char.isNumber || char == "-" || char == "_")
        }
        guard isValid else { throw OnlineSkinCatalogError.invalidSkinID(id) }
    }

    private nonisolated static func validateFrameName(_ name: String) throws {
        let isValid = !name.isEmpty
            && name.count <= 128
            && name.lowercased().hasSuffix(".png")
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("..")
            && name != ".png"
        guard isValid else { throw OnlineSkinCatalogError.invalidFrameName(name) }
    }

    private nonisolated static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= signature.count else { return false }
        return Array(data.prefix(signature.count)) == signature
    }
}

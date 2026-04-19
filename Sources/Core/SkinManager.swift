import AppKit
import CoreImage
import Defaults
import Observation

// ═══════════════════════════════════════════════════════════════
// MARK: - SkinInfo (auto-discovered from Resources/ or external path)
// ═══════════════════════════════════════════════════════════════
//
// To add a new skin: drop a folder of PNG frames into Resources/,
// done — no code changes needed.
//
// Users can also set an external skin directory in Settings.

struct SkinInfo: Identifiable, Hashable, Sendable {
    let id: String          // folder name, used as persistent key
    let displayName: String
}

// ═══════════════════════════════════════════════════════════════
// MARK: - SkinManager
// ═══════════════════════════════════════════════════════════════

@Observable
final class SkinManager: @unchecked Sendable {
    static let shared = SkinManager()
    private static let defaultSkinID = "cat"

    /// All discovered skins (bundled + external), sorted by id.
    private(set) var allSkins: [SkinInfo]

    private(set) var currentSkin: SkinInfo
    private var currentTheme: ThemeMode = .system
    private var frameCache: [String: [NSImage]] = [:]
    @ObservationIgnored private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        let skins = Self.discoverSkins(externalPath: Defaults[.externalSkinPath])
        self.allSkins = skins
        self.currentSkin = skins.first ?? SkinInfo(id: Self.defaultSkinID, displayName: Self.defaultSkinID)
    }

    /// Re-scan skins after external path changes.
    func reload() {
        allSkins = Self.discoverSkins(externalPath: Defaults[.externalSkinPath])
        if !allSkins.contains(where: { $0.id == currentSkin.id }) {
            let fallback = skin(for: Self.defaultSkinID)
            currentSkin = fallback
            Defaults[.skin] = fallback.id
        }
        clearCache()
    }

    /// Look up a skin by ID, falling back to the default skin.
    func skin(for id: String) -> SkinInfo {
        allSkins.first(where: { $0.id == id }) ?? allSkins.first ?? SkinInfo(id: Self.defaultSkinID, displayName: Self.defaultSkinID)
    }

    func setSkin(_ s: SkinInfo) { currentSkin = s }
    func setTheme(_ t: ThemeMode) { currentTheme = t; clearCache() }

    /// Returns cached or freshly-themed frames for the given (or current) skin.
    func frames(for skin: SkinInfo? = nil) -> [NSImage] {
        let s = skin ?? currentSkin
        let key = "\(s.id):\(themeHash)"
        if let cached = frameCache[key] { return cached }
        let base = loadFrames(for: s.id)
        guard !base.isEmpty else {
            // Skin frames not found — fall back to default
            let catKey = "\(Self.defaultSkinID):\(themeHash)"
            if let cached = frameCache[catKey] { return cached }
            let catFrames = loadFrames(for: Self.defaultSkinID)
            let themed = applyCurrentTheme(to: catFrames)
            frameCache[catKey] = themed
            return themed
        }
        let themed = applyCurrentTheme(to: base)
        frameCache[key] = themed
        return themed
    }

    /// Single frame by skin id + index (for settings preview).
    func frame(for skinID: String, frameIndex: Int) -> NSImage? {
        let all = frames(for: skin(for: skinID))
        guard frameIndex >= 0, frameIndex < all.count else { return nil }
        return all[frameIndex]
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Auto-Discovery
    // ═════════════════════════════════════════════════════════

    private static func discoverSkins(externalPath: String) -> [SkinInfo] {
        var seen = Set<String>()
        var skins: [SkinInfo] = []

        // 1. Bundled skins
        let bundled = scanDirectory(bundledSkinPaths())
        for s in bundled {
            if seen.insert(s.id).inserted { skins.append(s) }
        }

        // 2. External skins (override bundled if same id)
        if !externalPath.isEmpty {
            let expanded = (externalPath as NSString).expandingTildeInPath
            let external = scanDirectory([expanded])
            for s in external {
                if let idx = skins.firstIndex(where: { $0.id == s.id }) {
                    skins[idx] = s  // external overrides bundled
                } else if seen.insert(s.id).inserted {
                    skins.append(s)
                }
            }
        }

        return skins.sorted { $0.id < $1.id }
    }

    private static func bundledSkinPaths() -> [String] {
        let bundle = sharedResourceBundle()
        return [
            bundle.resourcePath,
            bundle.resourcePath.map { ($0 as NSString).appendingPathComponent("Resources") }
        ].compactMap { $0 }
    }

    private static func scanDirectory(_ paths: [String]) -> [SkinInfo] {
        let fm = FileManager.default
        var skins: [SkinInfo] = []

        for basePath in paths {
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for name in contents {
                let dirPath = (basePath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let hasPNG = (try? fm.contentsOfDirectory(atPath: dirPath))?.contains(where: { $0.hasSuffix(".png") }) ?? false
                guard hasPNG else { continue }
                skins.append(SkinInfo(id: name, displayName: name))
            }
        }
        return skins
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Frame Loading
    // ═════════════════════════════════════════════════════════

    private func loadFrames(for skinID: String) -> [NSImage] {
        let fm = FileManager.default
        let externalPath = Defaults[.externalSkinPath]

        // Search order: external first (user intent), then bundled
        var searchDirs = Self.bundledSkinPaths()
        if !externalPath.isEmpty {
            searchDirs.insert((externalPath as NSString).expandingTildeInPath, at: 0)
        }

        for basePath in searchDirs {
            let dirPath = (basePath as NSString).appendingPathComponent(skinID)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let pngs = ((try? fm.contentsOfDirectory(atPath: dirPath)) ?? [])
                .filter { $0.hasSuffix(".png") }
                .sorted(using: KeyPathComparator(\.self))

            let frames = pngs.compactMap { name -> NSImage? in
                let url = URL(fileURLWithPath: (dirPath as NSString).appendingPathComponent(name))
                let img = NSImage(contentsOf: url)
                img?.size = NSSize(width: 18, height: 18)
                return img
            }
            if !frames.isEmpty { return frames }
        }
        return []
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Theme
    // ═════════════════════════════════════════════════════════

    private var themeHash: String {
        switch currentTheme {
        case .system: return "sys"
        case .dark:  return "dark"
        case .light: return "light"
        }
    }

    private func clearCache() { frameCache.removeAll() }

    private func applyCurrentTheme(to images: [NSImage]) -> [NSImage] {
        let isDark: Bool
        switch currentTheme {
        case .system:
            isDark = MainActor.assumeIsolated {
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        case .dark:  isDark = true
        case .light: isDark = false
        }
        guard isDark else { return images }
        return images.map { recolorForDarkMode($0) }
    }

    private func recolorForDarkMode(_ image: NSImage) -> NSImage {
        guard let cgImg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let ciImage = CIImage(cgImage: cgImg)

        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(-1.0, forKey: kCIInputBrightnessKey)
        filter.setValue(1.2, forKey: kCIInputContrastKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage,
              let cgOutput = ciContext
                .createCGImage(output, from: CGRect(origin: .zero, size: CGSize(width: cgImg.width, height: cgImg.height)))
        else { return image }

        let result = NSImage(cgImage: cgOutput, size: image.size)
        result.isTemplate = false
        return result
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Shared Resource Bundle Helper
// ═══════════════════════════════════════════════════════════════

private func sharedResourceBundle() -> Bundle {
    if let rb = Bundle(path: Bundle.main.bundlePath + "/RunCatX_RunCatX.bundle") { return rb }
    return .main
}

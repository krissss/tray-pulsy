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
    static let defaultSkinID = "pulsy"

    /// All discovered skins (bundled + external), sorted by id.
    private(set) var allSkins: [SkinInfo]

    private(set) var currentSkin: SkinInfo
    private var currentTheme: ThemeMode = .system
    private let frameCache = NSCache<NSString, NSArray>()
    @ObservationIgnored private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init() {
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
    /// Also handles migration from old IDs without numeric prefix (e.g. "cat" → "01.cat").
    func skin(for id: String) -> SkinInfo {
        if let s = allSkins.first(where: { $0.id == id }) { return s }
        // Migration: old ID "cat" → match "01.cat" by suffix
        if let s = allSkins.first(where: { $0.id.hasSuffix(".\(id)") }) { return s }
        return allSkins.first ?? SkinInfo(id: Self.defaultSkinID, displayName: Self.defaultSkinID)
    }

    func setSkin(_ s: SkinInfo) { currentSkin = s }
    func setTheme(_ t: ThemeMode) { currentTheme = t; clearCache() }

    /// Build PulsyConfig from current Defaults.
    static func currentPulsyConfig() -> PulsyConfig {
        PulsyConfig(
            colorTheme: Defaults[.pulsyColorTheme],
            waveformStyle: Defaults[.pulsyWaveformStyle],
            lineWidth: Defaults[.pulsyLineWidth],
            glowIntensity: Defaults[.pulsyGlowIntensity],
            amplitudeSensitivity: Defaults[.pulsyAmplitudeSensitivity]
        )
    }

    /// Returns cached or freshly-themed frames for the given (or current) skin.
    func frames(for skin: SkinInfo? = nil) -> [NSImage] {
        let s = skin ?? currentSkin
        // Pulsy frames are always regenerated (config may have changed) — skip cache
        if s.id == "pulsy" {
            return loadFrames(for: s.id)
        }
        let key = "\(s.id):\(themeHash)" as NSString
        if let cached = frameCache.object(forKey: key) { return cached as! [NSImage] }
        let base = loadFrames(for: s.id)
        guard !base.isEmpty else {
            // Skin frames not found — fall back to default
            let catKey = "\(Self.defaultSkinID):\(themeHash)" as NSString
            if let cached = frameCache.object(forKey: catKey) { return cached as! [NSImage] }
            let catFrames = loadFrames(for: Self.defaultSkinID)
            let themed = applyCurrentTheme(to: catFrames)
            frameCache.setObject(themed as NSArray, forKey: catKey)
            return themed
        }
        let themed = applyCurrentTheme(to: base)
        frameCache.setObject(themed as NSArray, forKey: key)
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

    /// Virtual (programmatic) skins — always available, no PNG files needed.
    private static let virtualSkins: [SkinInfo] = [
        SkinInfo(id: "pulsy", displayName: "Pulsy")
    ]

    static func discoverSkins(externalPath: String) -> [SkinInfo] {
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

        // 3. Virtual skins (cannot be overridden by file-based skins)
        for s in virtualSkins {
            if let idx = skins.firstIndex(where: { $0.id == s.id }) {
                skins[idx] = s
            } else if seen.insert(s.id).inserted {
                skins.append(s)
            }
        }

        return skins.sorted { a, b in
            if a.id == "pulsy" { return true }
            if b.id == "pulsy" { return false }
            return a.id < b.id
        }
    }

    private static func bundledSkinPaths() -> [String] {
        let bundle = sharedResourceBundle()
        return [
            bundle.resourcePath.map { ($0 as NSString).appendingPathComponent("Resources/skins") },
            bundle.resourcePath.map { ($0 as NSString).appendingPathComponent("skins") },
            bundle.resourcePath,
            bundle.resourcePath.map { ($0 as NSString).appendingPathComponent("Resources") }
        ].compactMap { $0 }
    }

    static func scanDirectory(_ paths: [String]) -> [SkinInfo] {
        let ignoredExtensions: Set<String> = ["iconset", "lproj", "bundle"]
        let fm = FileManager.default
        var skins: [SkinInfo] = []

        for basePath in paths {
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for name in contents {
                let dirPath = (basePath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
                // Skip non-skin directories (.iconset, .lproj, .bundle, etc.)
                let ext = (name as NSString).pathExtension
                guard !ignoredExtensions.contains(ext) else { continue }
                let hasPNG = (try? fm.contentsOfDirectory(atPath: dirPath))?.contains(where: { $0.hasSuffix(".png") }) ?? false
                guard hasPNG else { continue }
                // Strip numeric prefix for display name: "01.cat" → "cat"
                let display: String
                if let dot = name.firstIndex(of: ".") {
                    display = String(name[name.index(after: dot)...])
                } else {
                    display = name
                }
                skins.append(SkinInfo(id: name, displayName: display))
            }
        }
        return skins
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Frame Loading
    // ═════════════════════════════════════════════════════════

    private func loadFrames(for skinID: String) -> [NSImage] {
        // Virtual skins — generated programmatically
        if skinID == "pulsy" {
            let config = Self.currentPulsyConfig()
            return PulsySkinRenderer.generateFrames(value: 0, config: config)
        }

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

    private func clearCache() { frameCache.removeAllObjects() }

    private func applyCurrentTheme(to images: [NSImage]) -> [NSImage] {
        let isDark: Bool
        switch currentTheme {
        case .system:
            isDark = MainActor.assumeIsolated {
                NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
    if let rb = Bundle(path: Bundle.main.bundlePath + "/TrayPulsy_TrayPulsy.bundle") { return rb }
    return .main
}

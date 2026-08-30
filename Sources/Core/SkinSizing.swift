import CoreGraphics

/// Single source of truth for how a skin sprite is sized on every display
/// surface (status bar, floating monitor, settings online-preview, skin
/// thumbnail, overview). Centralising it here keeps all surfaces — and the
/// web preview (`preview.js`) — showing sprites at the SAME relative size, and
/// means the two knobs live in exactly one place.
///
/// This mirrors the web preview, which renders
/// `natural × min(K=3, CAP=92/w, CAP/h, …)`. The mapping is:
///   - `refScale = K / CAP = 3/92`: the largest native sprite size still shown
///     at 1:1 in the gallery; smaller sprites are upscaled toward it.
///   - `maxFill`: longest-edge cap (fraction of the box) so a big sprite
///     (e.g. Sonic 38×39) can't dominate the panel — it ends up about as tall
///     as a tall sprite like Super Mario instead of filling the whole surface.
enum SkinSizing {
    static let refScale: CGFloat = 3.0 / 92.0
    static let maxFill: CGFloat = 0.8

    /// Displayed size of `source` inside `box`, preserving relative size across
    /// all surfaces and matching the web preview.
    static func displaySize(source: CGSize, box: CGSize) -> CGSize {
        let upscaleCap = min(box.width, box.height) * refScale
        let maxDimScale = maxFill * min(box.width, box.height) / max(source.width, source.height)
        let fit = min(upscaleCap, box.width / source.width, box.height / source.height, maxDimScale)
        return CGSize(width: source.width * fit, height: source.height * fit)
    }
}

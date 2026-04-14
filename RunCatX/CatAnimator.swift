import AppKit
import Combine

/// Drives frame-by-frame animation where playback speed scales with system usage.
///
/// Architecture mirrors Kyome22's original Menubar RunCat:
///   1. Timer in RunLoop.common mode (smooth during scroll/drag)
///   2. Direct NSImage assignment to statusItem.button.image
///   3. Timer recreated on each value update with new interval
///   4. Interval = base / clamp(value / divisor, 1, max)
final class CatAnimator: ObservableObject {
    @Published private(set) var currentFrame: NSImage
    @Published private(set) var framesPerSecond: Double = 0

    /// Base interval at "full speed" — 40fps baseline
    private let baseInterval: TimeInterval = 0.025
    private let valueDivisor: Double = 5.0
    private let valueClampMax: Double = 20.0

    private var runnerTimer: Timer?
    private var frameIndex: Int = 0
    private var frames: [NSImage] = []
    private var currentValue: Double = 0
    private var fpsLimit: FPSLimit = .fps40

    init(skinManager: SkinManager) {
        self.frames = skinManager.frames()
        self.currentFrame = frames.first ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    deinit { stop() }

    // MARK: - Public

    func updateValue(_ value: Double) {
        currentValue = max(0, min(100, value))
        restartTimerWithCurrentInterval()
    }

    func setFPSLimit(_ limit: FPSLimit) {
        fpsLimit = limit
        restartTimerWithCurrentInterval()
    }

    func changeSkin(to newFrames: [NSImage]) {
        frames = newFrames; frameIndex = 0
        if !frames.isEmpty { currentFrame = frames[0] }
        restartTimerWithCurrentInterval()
    }

    func start() { restartTimerWithCurrentInterval() }
    func stop() { runnerTimer?.invalidate(); runnerTimer = nil }

    // MARK: - Core

    /// Recreates timer with interval derived from current value × FPS limit rate.
    private func restartTimerWithCurrentInterval() {
        runnerTimer?.invalidate()

        let clampedValue = max(1.0, min(valueClampMax, currentValue / valueDivisor))
        let rawInterval = baseInterval / clampedValue
        let interval = rawInterval / fpsLimit.rateMultiplier
        framesPerSecond = 1.0 / interval

        runnerTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: true
        )
        RunLoop.current.add(runnerTimer!, forMode: .common)
    }

    @objc private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        currentFrame = frames[frameIndex]
    }
}

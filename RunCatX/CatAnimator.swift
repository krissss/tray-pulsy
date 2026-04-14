import AppKit

/// Drives frame-by-frame animation where playback speed scales with system usage.
///
/// Architecture mirrors Kyome22's original Menubar RunCat (PROVEN pattern):
///   1. Timer in RunLoop.common mode (smooth during scroll/drag)
///   2. Direct NSImage assignment via callback — zero overhead
///   3. Timer recreated ONLY when interval changes significantly (>5% delta)
///   4. Original interval formula: 0.2 / clamp(usage / 5.0, 1.0, 20.0)
///      → 5 fps at 0% CPU (idle/breathing) → 100 fps at 100% CPU (blazing)
final class CatAnimator {

    // MARK: - Callback (replaces @Published + Combine — zero overhead)

    /// Called on main thread every time the frame advances.
    var onFrameUpdate: ((NSImage, Double) -> Void)?

    /// MARK: - Config

    private let valueDivisor: Double = 5.0
    private let valueClampMin: Double = 1.0
    private let valueClampMax: Double = 20.0

    // MARK: - State

    private var runnerTimer: Timer?
    private var frameIndex: Int = 0
    private var frames: [NSImage] = []
    private var currentValue: Double = 0
    private var fpsLimit: FPSLimit = .fps40
    private var currentInterval: TimeInterval = 0.2 // start at slowest (idle)

    // MARK: - Init

    init(initialFrames: [NSImage]) {
        self.frames = initialFrames
    }

    deinit { stop() }

    // MARK: - Public API

    /// Update the driving value (CPU% or Memory%). Recreates timer only if speed changes >5%.
    func updateValue(_ value: Double) {
        currentValue = max(0, min(100, value))
        maybeRestartTimer()
    }

    func setFPSLimit(_ limit: FPSLimit) {
        fpsLimit = limit
        forceRestartTimer()
    }

    func changeSkin(to newFrames: [NSImage]) {
        frames = newFrames
        frameIndex = 0
        forceRestartTimer()
        // Immediately show first frame
        if !frames.isEmpty {
            onFrameUpdate?(frames[0], computeFPS())
        }
    }

    func start() { forceRestartTimer() }
    func stop() {
        runnerTimer?.invalidate()
        runnerTimer = nil
    }

    /// Current computed FPS (for display purposes).
    func computeFPS() -> Double {
        guard currentInterval > 0 else { return 0 }
        return 1.0 / currentInterval
    }

    // MARK: - Core: Original Formula

    /// Original RunCat interval formula (exact match):
    ///   interval = 0.2 / clamp(value / 5.0, 1.0, 20.0)
    ///   → 0.2s (5fps) at 0% usage  →  0.01s (100fps) at 100% usage
    private func computeInterval() -> TimeInterval {
        let clamped = max(valueClampMin, min(valueClampMax, currentValue / valueDivisor))
        let raw = 0.2 / clamped          // ← ORIGINAL base value
        return raw / fpsLimit.rateMultiplier
    }

    /// Only recreate timer if interval changed more than 5%.
    /// Avoids micro-stutter from destroying/recreating timer every second.
    private func maybeRestartTimer() {
        let newInterval = computeInterval()
        let delta = abs(newInterval - currentInterval) / max(currentInterval, 0.001)
        guard delta > 0.05 else { return } // skip if < 5% change
        currentInterval = newInterval
        createTimer(with: newInterval)
    }

    /// Unconditionally recreate timer (for skin/fps limit changes).
    private func forceRestartTimer() {
        currentInterval = computeInterval()
        createTimer(with: currentInterval)
    }

    // MARK: - Timer Management

    private func createTimer(with interval: TimeInterval) {
        // Invalidate old
        runnerTimer?.invalidate()
        runnerTimer = nil

        guard !frames.isEmpty else { return }

        // Create new timer on RunLoop.main in .common mode
        // (.common = keeps running during scroll/drag/menu tracking)
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
        let img = frames[frameIndex]
        onFrameUpdate?(img, computeFPS())
    }
}

import AppKit

/// Drives frame-by-frame animation where playback speed scales with system usage.
final class TrayAnimator: @unchecked Sendable {

    var onFrameUpdate: ((NSImage) -> Void)?

    private var runnerTimer: Timer?
    private var frameIndex: Int = 0
    private var frames: [NSImage] = []
    private var currentValue: Double = 0
    private var fpsLimit: FPSLimit = .fps40
    private var reverseAnimationSpeed: Bool = false
    private var skinAnimationSpeed: SkinAnimationSpeed = .normal
    private var currentInterval: TimeInterval = 0.10

    /// Current playback FPS (read-only, for UI display).
    private(set) var currentFPS: Double = 0

    init(initialFrames: [NSImage]) {
        self.frames = initialFrames
    }

    deinit { stop() }

    func updateValue(_ value: Double) {
        currentValue = max(0, min(100, value))
        maybeRestartTimer()
    }

    func setFPSLimit(_ limit: FPSLimit) {
        fpsLimit = limit
        forceRestartTimer()
    }

    func setReverseAnimationSpeed(_ isReversed: Bool) {
        reverseAnimationSpeed = isReversed
        forceRestartTimer()
    }

    func setSkinAnimationSpeed(_ speed: SkinAnimationSpeed) {
        skinAnimationSpeed = speed
        forceRestartTimer()
    }

    func changeSkin(to newFrames: [NSImage]) {
        frames = newFrames
        frameIndex = 0
        forceRestartTimer()
        if let first = frames.first {
            onFrameUpdate?(first)
        }
    }

    /// Replace frames without resetting animation position (for dynamic skins like Pulsy).
    func updateFrames(_ newFrames: [NSImage]) {
        guard !newFrames.isEmpty else { return }
        frames = newFrames
        if frameIndex >= frames.count { frameIndex = 0 }
    }

    func start() { forceRestartTimer() }
    func stop() {
        runnerTimer?.invalidate()
        runnerTimer = nil
    }

    func pause() { stop() }

    func resume() {
        guard runnerTimer == nil else { return }
        forceRestartTimer()
    }

    // MARK: - Core

    /// Linear mapping scaled by fpsLimit.rateMultiplier:
    ///   fps40 (1.0x): ~10fps idle → ~40fps at 75%+
    ///   fps10 (4.0x): ~2.5fps idle → ~10fps at 75%+
    /// 低帧兜底：帧数少于 lowFrameThreshold 时，强制最小整圈时长 minLoopDuration，
    /// 避免低帧皮肤频闪。仅影响低帧皮肤；≥ threshold 的高帧皮肤观感与改动前完全一致。
    func computeInterval() -> TimeInterval {
        let normalizedValue = reverseAnimationSpeed ? 100.0 - currentValue : currentValue
        let base = max(0.025, 0.10 - 0.12 * (normalizedValue / 100.0))
        var interval = base * fpsLimit.rateMultiplier * skinAnimationSpeed.intervalMultiplier

        let lowFrameThreshold = 5
        // Min loop for low-frame skins: 0.12s (was 0.25s, originally 0.4s).
        // 0.4s pinned 2-frame to 5 FPS / 4-frame to 10 FPS (slower than idle,
        // not load-responsive). 0.25s raised to 8/16 FPS but still felt slow at
        // high load. 0.12s raises the cap to ~17 FPS (2-frame) / ~33 FPS
        // (4-frame): brisk at high load while still avoiding the worst strobe
        // (a 2-frame flip at 40 FPS). Tune downwards (e.g. 0.08 → 25 FPS for
        // 2-frame) only if you can tolerate more flicker.
        let minLoopDuration: TimeInterval = 0.12
        let count = frames.count
        if count > 0, count < lowFrameThreshold {
            let loop = interval * Double(count)
            if loop < minLoopDuration {
                interval = minLoopDuration / Double(count)
            }
        }
        return interval
    }

    private func maybeRestartTimer() {
        let newInterval = computeInterval()
        let delta = abs(newInterval - currentInterval) / max(currentInterval, 0.001)
        guard delta > 0.05 else { return }
        currentInterval = newInterval
        createTimer(with: newInterval)
    }

    private func forceRestartTimer() {
        currentInterval = computeInterval()
        createTimer(with: currentInterval)
    }

    private func createTimer(with interval: TimeInterval) {
        runnerTimer?.invalidate()
        runnerTimer = nil

        guard !frames.isEmpty else {
            currentFPS = 0
            return
        }
        currentFPS = interval > 0 ? 1.0 / interval : 0

        runnerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        onFrameUpdate?(frames[frameIndex])
    }
}

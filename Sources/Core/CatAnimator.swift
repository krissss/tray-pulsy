import AppKit

/// Drives frame-by-frame animation where playback speed scales with system usage.
final class CatAnimator {

    var onFrameUpdate: ((NSImage, Double) -> Void)?

    private var runnerTimer: Timer?
    private var frameIndex: Int = 0
    private var frames: [NSImage] = []
    private var currentValue: Double = 0
    private var fpsLimit: FPSLimit = .fps40
    private var currentInterval: TimeInterval = 0.10

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

    func changeSkin(to newFrames: [NSImage]) {
        frames = newFrames
        frameIndex = 0
        forceRestartTimer()
        if !frames.isEmpty {
            onFrameUpdate?(frames[0], computeFPS())
        }
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

    func computeFPS() -> Double {
        guard currentInterval > 0 else { return 0 }
        return 1.0 / currentInterval
    }

    // MARK: - Core

    /// Linear mapping scaled by fpsLimit.rateMultiplier:
    ///   fps40 (1.0x): ~10fps idle → ~40fps at 75%+
    ///   fps10 (4.0x): ~2.5fps idle → ~10fps at 75%+
    private func computeInterval() -> TimeInterval {
        let base = max(0.025, 0.10 - 0.12 * (currentValue / 100.0))
        return base * fpsLimit.rateMultiplier
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

        guard !frames.isEmpty else { return }

        runnerTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: true
        )
        if let timer = runnerTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    @objc private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        onFrameUpdate?(frames[frameIndex], computeFPS())
    }
}

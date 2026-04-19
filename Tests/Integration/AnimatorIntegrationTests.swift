import AppKit
import XCTest
@testable import TrayPulsy

// MARK: - Animator Integration Tests
//
// Tests TrayAnimator with real Timer + RunLoop interaction.

final class AnimatorIntegrationTests: XCTestCase {

    private func spinRunLoop(seconds: TimeInterval = 0.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeFrames(_ count: Int) -> [NSImage] {
        Array(repeating: NSImage(size: NSSize(width: 18, height: 18)), count: count)
    }

    // MARK: - Timer fires → frame callbacks

    func testTimerFires_advancesFrames() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        var received: [NSImage] = []
        animator.onFrameUpdate = { received.append($0) }

        animator.start()
        spinRunLoop(seconds: 0.6)
        animator.stop()

        XCTAssertGreaterThanOrEqual(received.count, 2)
    }

    func testHighLoad_firesFasterThanIdle() {
        let idle = TrayAnimator(initialFrames: makeFrames(5))
        var idleCount = 0
        idle.onFrameUpdate = { _ in idleCount += 1 }
        idle.updateValue(0)
        idle.start()

        let loaded = TrayAnimator(initialFrames: makeFrames(5))
        var loadedCount = 0
        loaded.onFrameUpdate = { _ in loadedCount += 1 }
        loaded.updateValue(100)
        loaded.start()

        spinRunLoop(seconds: 0.6)
        idle.stop(); loaded.stop()

        XCTAssertGreaterThan(loadedCount, idleCount)
    }

    func testFPSLimit_slowsDownAnimation() {
        let fast = TrayAnimator(initialFrames: makeFrames(5))
        var fastCount = 0
        fast.onFrameUpdate = { _ in fastCount += 1 }
        fast.setFPSLimit(.fps40)
        fast.start()

        let slow = TrayAnimator(initialFrames: makeFrames(5))
        var slowCount = 0
        slow.onFrameUpdate = { _ in slowCount += 1 }
        slow.setFPSLimit(.fps10)
        slow.start()

        spinRunLoop(seconds: 0.6)
        fast.stop(); slow.stop()

        XCTAssertGreaterThan(fastCount, slowCount * 2)
    }

    func testPauseStopsCallbacks() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        var count = 0
        animator.onFrameUpdate = { _ in count += 1 }
        animator.start()
        spinRunLoop(seconds: 0.3)
        animator.pause()

        let countAfterPause = count
        spinRunLoop(seconds: 0.3)

        XCTAssertEqual(count, countAfterPause, "No more callbacks after pause")
        animator.stop()
    }

    // MARK: - maybeRestartTimer threshold

    func testSmallValueChange_doesNotRestartTimer() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.start()
        let fpsBefore = animator.currentFPS

        animator.updateValue(1)
        XCTAssertEqual(animator.currentFPS, fpsBefore, "Small change should not affect FPS")
        animator.stop()
    }

    func testLargeValueChange_restartsTimer() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.updateValue(0)
        animator.start()
        let fpsBefore = animator.currentFPS

        animator.updateValue(80)
        XCTAssertNotEqual(animator.currentFPS, fpsBefore, "Large change should change FPS")
        animator.stop()
    }

    // MARK: - Full lifecycle

    func testFullLifecycle_startUpdateChangeSkinPauseResumeStop() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        var count = 0
        animator.onFrameUpdate = { _ in count += 1 }

        // Start
        animator.start()
        spinRunLoop(seconds: 0.2)
        XCTAssertGreaterThan(count, 0)

        // Update value (large change)
        animator.updateValue(90)
        let fpsHigh = animator.currentFPS
        XCTAssertGreaterThan(fpsHigh, 0)

        // Change skin
        let newFrames = makeFrames(5)
        animator.changeSkin(to: newFrames)
        spinRunLoop(seconds: 0.2)

        // Set FPS limit
        animator.setFPSLimit(.fps20)
        spinRunLoop(seconds: 0.2)

        // Pause
        let countBeforePause = count
        animator.pause()
        spinRunLoop(seconds: 0.2)
        XCTAssertEqual(count, countBeforePause, "No callbacks while paused")

        // Resume
        animator.resume()
        spinRunLoop(seconds: 0.2)
        XCTAssertGreaterThan(count, countBeforePause, "Callbacks resume after resume")

        // Stop
        let countBeforeStop = count
        animator.stop()
        spinRunLoop(seconds: 0.2)
        XCTAssertEqual(count, countBeforeStop, "No callbacks after stop")
    }

    // MARK: - Edge cases

    func testChangeSkinToEmptyWhileRunning_noCallbacks() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        var count = 0
        animator.onFrameUpdate = { _ in count += 1 }
        animator.start()
        spinRunLoop(seconds: 0.2)
        let countBefore = count

        animator.changeSkin(to: [])
        spinRunLoop(seconds: 0.2)

        XCTAssertEqual(count, countBefore, "No callbacks after switching to empty frames")
        XCTAssertEqual(animator.currentFPS, 0)
    }

    func testRapidValueUpdates_onlyFinalIntervalMatters() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.start()

        // Rapidly update values — only large deltas should trigger timer restart
        for v in stride(from: 0.0, through: 100.0, by: 1.0) {
            animator.updateValue(v)
        }

        // Should end up at high-load FPS (~40 for fps40)
        XCTAssertGreaterThan(animator.currentFPS, 20)
        animator.stop()
    }
}

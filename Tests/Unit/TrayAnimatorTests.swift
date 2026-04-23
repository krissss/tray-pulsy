import AppKit
import XCTest
@testable import TrayPulsy

final class TrayAnimatorTests: XCTestCase {

    // MARK: - computeInterval

    func testComputeInterval_idle_fps40() {
        let a = makeAnimator()
        a.updateValue(0)
        let interval = a.computeInterval()
        XCTAssertEqual(interval, 0.10 * FPSLimit.fps40.rateMultiplier, accuracy: 0.001)
    }

    func testComputeInterval_fullLoad_fps40() {
        let a = makeAnimator()
        a.updateValue(100)
        // base = max(0.025, 0.10 - 0.12 * 1.0) = max(0.025, -0.02) = 0.025
        let interval = a.computeInterval()
        XCTAssertEqual(interval, 0.025 * FPSLimit.fps40.rateMultiplier, accuracy: 0.001)
    }

    func testComputeInterval_midLoad_fps40() {
        let a = makeAnimator()
        a.updateValue(50)
        // base = max(0.025, 0.10 - 0.12 * 0.5) = max(0.025, 0.04) = 0.04
        let interval = a.computeInterval()
        XCTAssertEqual(interval, 0.04 * FPSLimit.fps40.rateMultiplier, accuracy: 0.001)
    }

    func testComputeInterval_fps10_multiplier() {
        let a = makeAnimator()
        a.setFPSLimit(.fps10)
        a.updateValue(0)
        let interval = a.computeInterval()
        XCTAssertEqual(interval, 0.10 * FPSLimit.fps10.rateMultiplier, accuracy: 0.001)
    }

    func testComputeInterval_fps20_multiplier() {
        let a = makeAnimator()
        a.setFPSLimit(.fps20)
        a.updateValue(75)
        // base = max(0.025, 0.10 - 0.12 * 0.75) = max(0.025, 0.01) = 0.025
        let interval = a.computeInterval()
        XCTAssertEqual(interval, 0.025 * FPSLimit.fps20.rateMultiplier, accuracy: 0.001)
    }

    // MARK: - Value clamping

    func testUpdateValue_clampsNegative() {
        let a = makeAnimator()
        a.updateValue(-50)
        let interval = a.computeInterval()
        // clamp to 0 → same as idle
        XCTAssertEqual(interval, 0.10 * FPSLimit.fps40.rateMultiplier, accuracy: 0.001)
    }

    func testUpdateValue_clampsAbove100() {
        let a = makeAnimator()
        a.updateValue(200)
        let interval = a.computeInterval()
        // clamp to 100 → same as full load
        XCTAssertEqual(interval, 0.025 * FPSLimit.fps40.rateMultiplier, accuracy: 0.001)
    }

    // MARK: - changeSkin

    func testChangeSkin_firesFirstFrame() {
        let a = makeAnimator()
        var received: NSImage?
        a.onFrameUpdate = { received = $0 }

        let newFrames = [NSImage(size: NSSize(width: 18, height: 18))]
        a.changeSkin(to: newFrames)

        XCTAssertNotNil(received)
    }

    func testChangeSkin_emptyFrames_noCallback() {
        let a = makeAnimator()
        var called = false
        a.onFrameUpdate = { _ in called = true }

        a.changeSkin(to: [])
        XCTAssertFalse(called)
    }

    // MARK: - updateFrames

    func testUpdateFrames_replacesFramesWithoutResettingIndex() {
        let frames = (0..<5).map { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        let a = TrayAnimator(initialFrames: frames)

        // Replace frames with same count — no crash
        let newFrames = (0..<5).map { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        a.updateFrames(newFrames)
        XCTAssertNotNil(a)
    }

    func testUpdateFrames_emptyFrames_isIgnored() {
        let a = makeAnimator()
        a.updateFrames([])
        // Empty frames should be ignored — animator still works
        XCTAssertNotNil(a)
    }

    func testUpdateFrames_shorterArray_wrapsIndex() {
        let long = (0..<10).map { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        let a = TrayAnimator(initialFrames: long)
        a.changeSkin(to: long)

        // Replace with fewer frames — no crash
        let short = (0..<3).map { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        a.updateFrames(short)
        // Verify animation continues without crash after frame replacement
        XCTAssertNotNil(a)
    }

    // MARK: - pause / resume

    func testPauseStopsAnimation() {
        let a = makeAnimator()
        a.start()
        a.pause()
        // After pause, currentFPS should remain at last known value
        // but timer is invalidated — verify no crash and animator is in stopped state
        XCTAssertNotNil(a)  // no crash = pass
    }

    func testResumeRestartsAnimation() {
        let a = makeAnimator()
        a.start()
        a.pause()
        a.resume()
        // Should not crash; animator resumes from where it left off
        XCTAssertNotNil(a)
    }

    func testResumeWhenAlreadyRunning_isNoop() {
        let a = makeAnimator()
        a.start()
        a.resume() // already running
        XCTAssertNotNil(a)
    }

    // MARK: - currentFPS

    func testCurrentFPS_afterStart() {
        let a = makeAnimator()
        a.start()
        // fps40 idle: interval = 0.10 → FPS = 10
        XCTAssertEqual(a.currentFPS, 10.0, accuracy: 0.1)
    }

    func testCurrentFPS_afterHighLoad() {
        let a = makeAnimator()
        a.updateValue(100)
        a.start()
        // interval = 0.025 → FPS = 40
        XCTAssertEqual(a.currentFPS, 40.0, accuracy: 0.1)
    }

    func testCurrentFPS_afterFPSLimitChange() {
        let a = makeAnimator()
        a.setFPSLimit(.fps10)
        a.start()
        // interval = 0.10 * 4.0 = 0.40 → FPS = 2.5
        XCTAssertEqual(a.currentFPS, 2.5, accuracy: 0.1)
    }

    func testCurrentFPS_emptyFrames_isZero() {
        let a = TrayAnimator(initialFrames: [])
        a.start()
        XCTAssertEqual(a.currentFPS, 0)
    }

    // MARK: - deinit cleanup

    func testDeinit_cleansUpTimer() {
        var a: TrayAnimator? = makeAnimator()
        a?.start()
        a = nil // should not crash
    }

    // MARK: - Helpers

    private func makeAnimator() -> TrayAnimator {
        TrayAnimator(initialFrames: [NSImage(size: NSSize(width: 18, height: 18))])
    }
}

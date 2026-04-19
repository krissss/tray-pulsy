import AppKit
import XCTest
@testable import TrayPulsy

// MARK: - Pipeline Integration Tests
//
// End-to-end: SpeedSource → normalizeForAnimation → TrayAnimator speed.

final class PipelineIntegrationTests: XCTestCase {

    private func makeFrames(_ count: Int) -> [NSImage] {
        Array(repeating: NSImage(size: NSSize(width: 18, height: 18)), count: count)
    }

    // MARK: - CPU pipeline

    func testCPU_highLoad_speedsUpAnimation() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.start()

        let idleNormalized = SpeedSource.cpu.normalizeForAnimation(5.0)
        animator.updateValue(idleNormalized)
        let fpsIdle = animator.currentFPS

        let loadedNormalized = SpeedSource.cpu.normalizeForAnimation(85.0)
        animator.updateValue(loadedNormalized)
        let fpsLoaded = animator.currentFPS

        XCTAssertGreaterThan(fpsLoaded, fpsIdle)
        animator.stop()
    }

    // MARK: - Memory pipeline

    func testMemory_normalizeProducesReasonableRange() {
        let idle = SpeedSource.memory.normalizeForAnimation(70)
        let full = SpeedSource.memory.normalizeForAnimation(100)
        let mid = SpeedSource.memory.normalizeForAnimation(85)

        XCTAssertEqual(idle, 0, accuracy: 0.01)
        XCTAssertEqual(full, 100, accuracy: 0.01)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 100)
    }

    func testMemory_idleAndFullDriveAnimator() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.start()

        let idle = SpeedSource.memory.normalizeForAnimation(70)
        animator.updateValue(idle)
        let fpsIdle = animator.currentFPS

        let full = SpeedSource.memory.normalizeForAnimation(100)
        animator.updateValue(full)
        let fpsFull = animator.currentFPS

        XCTAssertGreaterThan(fpsFull, fpsIdle)
        animator.stop()
    }

    // MARK: - Disk pipeline

    func testDisk_normalizeProducesReasonableRange() {
        let idle = SpeedSource.disk.normalizeForAnimation(60)
        let full = SpeedSource.disk.normalizeForAnimation(100)

        XCTAssertEqual(idle, 0, accuracy: 0.01)
        XCTAssertEqual(full, 100, accuracy: 0.01)
    }

    func testDisk_idleAndFullDriveAnimator() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.start()

        let idle = SpeedSource.disk.normalizeForAnimation(60)
        animator.updateValue(idle)
        let fpsIdle = animator.currentFPS

        let full = SpeedSource.disk.normalizeForAnimation(100)
        animator.updateValue(full)
        let fpsFull = animator.currentFPS

        XCTAssertGreaterThan(fpsFull, fpsIdle)
        animator.stop()
    }

    // MARK: - GPU pipeline (passthrough like CPU)

    func testGPU_passthroughDrivesAnimator() {
        let animator = TrayAnimator(initialFrames: makeFrames(3))
        animator.start()

        let idle = SpeedSource.gpu.normalizeForAnimation(10)
        animator.updateValue(idle)
        let fpsIdle = animator.currentFPS

        let full = SpeedSource.gpu.normalizeForAnimation(95)
        animator.updateValue(full)
        let fpsFull = animator.currentFPS

        XCTAssertGreaterThan(fpsFull, fpsIdle)
        animator.stop()
    }

    // MARK: - All sources produce consistent ranges

    func testAllSources_highValue_drivesAnimatorToHighFPS() {
        for source in SpeedSource.allCases {
            let animator = TrayAnimator(initialFrames: makeFrames(3))
            let normalized = source.normalizeForAnimation(95)
            animator.updateValue(normalized)
            animator.start()

            XCTAssertGreaterThan(animator.currentFPS, 0, "\(source.label) should produce positive FPS at high load")
            animator.stop()
        }
    }
}

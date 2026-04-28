import Defaults
import XCTest
@testable import TrayPulsy

final class SettingsStoreTests: XCTestCase {

    // MARK: - SpeedSource.normalizeForAnimation

    func testNormalize_cpu_passthrough() {
        XCTAssertEqual(SpeedSource.cpu.normalizeForAnimation(50), 50)
        XCTAssertEqual(SpeedSource.cpu.normalizeForAnimation(0), 0)
        XCTAssertEqual(SpeedSource.cpu.normalizeForAnimation(100), 100)
    }

    func testNormalize_gpu_passthrough() {
        XCTAssertEqual(SpeedSource.gpu.normalizeForAnimation(30), 30)
    }

    func testNormalize_memory_atBaseline_returnsZero() {
        // Memory idle ≈ 70% baseline (total - free - purgeable - external)
        XCTAssertEqual(SpeedSource.memory.normalizeForAnimation(70), 0, accuracy: 0.01)
    }

    func testNormalize_memory_aboveBaseline() {
        // (85 - 70) / (100 - 70) * 100 = 15/30 * 100 = 50
        let result = SpeedSource.memory.normalizeForAnimation(85)
        XCTAssertEqual(result, 50.0, accuracy: 0.01)
    }

    func testNormalize_memory_belowBaseline_clampsToZero() {
        XCTAssertEqual(SpeedSource.memory.normalizeForAnimation(50), 0, accuracy: 0.01)
    }

    func testNormalize_disk_atBaseline_returnsZero() {
        // Disk idle ≈ 60% baseline
        XCTAssertEqual(SpeedSource.disk.normalizeForAnimation(60), 0, accuracy: 0.01)
    }

    func testNormalize_disk_aboveBaseline() {
        // (80 - 60) / (100 - 60) * 100 = 20/40 * 100 = 50
        XCTAssertEqual(SpeedSource.disk.normalizeForAnimation(80), 50, accuracy: 0.01)
    }

    func testNormalize_disk_belowBaseline_clampsToZero() {
        XCTAssertEqual(SpeedSource.disk.normalizeForAnimation(30), 0, accuracy: 0.01)
    }

    // MARK: - FPSLimit.rateMultiplier

    func testFPSLimit_rateMultipliers() {
        XCTAssertEqual(FPSLimit.fps10.rateMultiplier, 4.0)
        XCTAssertEqual(FPSLimit.fps20.rateMultiplier, 2.0)
        XCTAssertEqual(FPSLimit.fps30.rateMultiplier, 1.33)
        XCTAssertEqual(FPSLimit.fps40.rateMultiplier, 1.0)
    }

    func testFPSLimit_allCases() {
        XCTAssertEqual(FPSLimit.allCases.count, 4)
    }

    // MARK: - SampleInterval.seconds

    func testSampleInterval_seconds() {
        XCTAssertEqual(SampleInterval.halfSec.seconds, 0.5)
        XCTAssertEqual(SampleInterval.oneSec.seconds, 1.0)
        XCTAssertEqual(SampleInterval.twoSec.seconds, 2.0)
        XCTAssertEqual(SampleInterval.threeSec.seconds, 3.0)
        XCTAssertEqual(SampleInterval.fiveSec.seconds, 5.0)
        XCTAssertEqual(SampleInterval.tenSec.seconds, 10.0)
    }

    func testSampleInterval_allCases() {
        XCTAssertEqual(SampleInterval.allCases.count, 6)
    }

    // MARK: - ThemeMode.isDarkOverride

    func testThemeMode_isDarkOverride() {
        XCTAssertNil(ThemeMode.system.isDarkOverride)
        XCTAssertEqual(ThemeMode.light.isDarkOverride, false)
        XCTAssertEqual(ThemeMode.dark.isDarkOverride, true)
    }

    func testThemeMode_allCases() {
        XCTAssertEqual(ThemeMode.allCases.count, 3)
    }

    // MARK: - SpeedSource properties (non-L10n)

    func testSpeedSource_requiredMetric() {
        XCTAssertEqual(SpeedSource.cpu.requiredMetric, .cpu)
        XCTAssertEqual(SpeedSource.gpu.requiredMetric, .gpu)
        XCTAssertEqual(SpeedSource.memory.requiredMetric, .memory)
        XCTAssertEqual(SpeedSource.disk.requiredMetric, .disk)
    }

    func testSpeedSource_systemImages() {
        XCTAssertEqual(SpeedSource.cpu.systemImage, "cpu")
        XCTAssertEqual(SpeedSource.gpu.systemImage, "square.on.square")
        XCTAssertEqual(SpeedSource.memory.systemImage, "memorychip")
        XCTAssertEqual(SpeedSource.disk.systemImage, "internaldrive")
    }
}

import AppKit
import XCTest
@testable import TrayPulsy

final class ThresholdTests: XCTestCase {

    // MARK: - MetricThresholds defaults

    func testDefaultThresholds_cpu() {
        let t = ThresholdConfig.defaults
        XCTAssertEqual(t.cpu.warning, 70)
        XCTAssertEqual(t.cpu.critical, 90)
    }

    func testDefaultThresholds_gpu() {
        let t = ThresholdConfig.defaults
        XCTAssertEqual(t.gpu.warning, 70)
        XCTAssertEqual(t.gpu.critical, 90)
    }

    func testDefaultThresholds_memory() {
        let t = ThresholdConfig.defaults
        XCTAssertEqual(t.memory.warning, 80)
        XCTAssertEqual(t.memory.critical, 95)
    }

    func testDefaultThresholds_disk() {
        let t = ThresholdConfig.defaults
        XCTAssertEqual(t.disk.warning, 80)
        XCTAssertEqual(t.disk.critical, 95)
    }

    func testDefaultThresholds_networkDown() {
        let t = ThresholdConfig.defaults
        XCTAssertEqual(t.networkDown.warning, 1_000_000)
        XCTAssertEqual(t.networkDown.critical, 10_000_000)
    }

    func testDefaultThresholds_networkUp() {
        let t = ThresholdConfig.defaults
        XCTAssertEqual(t.networkUp.warning, 500_000)
        XCTAssertEqual(t.networkUp.critical, 5_000_000)
    }

    // MARK: - color(forRawValue:thresholds:) — CPU

    func testColor_belowWarning_textColor() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.cpu.color(forRawValue: 50, thresholds: config)
        XCTAssertEqual(color, .textColor)
    }

    func testColor_atWarning_yellow() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.cpu.color(forRawValue: 70, thresholds: config)
        XCTAssertEqual(color, .systemYellow)
    }

    func testColor_betweenWarningAndCritical_yellow() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.cpu.color(forRawValue: 85, thresholds: config)
        XCTAssertEqual(color, .systemYellow)
    }

    func testColor_atCritical_red() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.cpu.color(forRawValue: 90, thresholds: config)
        XCTAssertEqual(color, .systemRed)
    }

    func testColor_aboveCritical_red() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.cpu.color(forRawValue: 100, thresholds: config)
        XCTAssertEqual(color, .systemRed)
    }

    func testColor_zero_textColor() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.cpu.color(forRawValue: 0, thresholds: config)
        XCTAssertEqual(color, .textColor)
    }

    // MARK: - color for network metrics

    func testColor_networkDown_belowWarning_textColor() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.networkDown.color(forRawValue: 500_000, thresholds: config)
        XCTAssertEqual(color, .textColor)
    }

    func testColor_networkDown_atWarning_yellow() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.networkDown.color(forRawValue: 1_000_000, thresholds: config)
        XCTAssertEqual(color, .systemYellow)
    }

    func testColor_networkUp_atCritical_red() {
        let config = ThresholdConfig.defaults
        let color = MetricDisplayItem.networkUp.color(forRawValue: 5_000_000, thresholds: config)
        XCTAssertEqual(color, .systemRed)
    }

    // MARK: - All metrics color boundaries

    func testColor_allMetrics_boundaryValues() {
        let config = ThresholdConfig.defaults
        for item in MetricDisplayItem.allCases {
            let t = config[keyPath: item.thresholdKeyPath]
            // Below warning → textColor
            XCTAssertEqual(item.color(forRawValue: t.warning - 1, thresholds: config), .textColor,
                           "\(item.rawValue) below warning should be textColor")
            // At warning → yellow
            XCTAssertEqual(item.color(forRawValue: t.warning, thresholds: config), .systemYellow,
                           "\(item.rawValue) at warning should be yellow")
            // At critical → red
            XCTAssertEqual(item.color(forRawValue: t.critical, thresholds: config), .systemRed,
                           "\(item.rawValue) at critical should be red")
        }
    }

    // MARK: - thresholdKeyPath round-trip

    func testThresholdKeyPath_roundTrip() {
        var config = ThresholdConfig.defaults
        for item in MetricDisplayItem.allCases {
            config[keyPath: item.thresholdKeyPath] = MetricThresholds(warning: 42, critical: 84)
            XCTAssertEqual(config[keyPath: item.thresholdKeyPath].warning, 42)
            XCTAssertEqual(config[keyPath: item.thresholdKeyPath].critical, 84)
        }
    }

    // MARK: - unitLabel

    func testUnitLabel_percentMetrics() {
        XCTAssertEqual(MetricDisplayItem.cpu.unitLabel, "%")
        XCTAssertEqual(MetricDisplayItem.gpu.unitLabel, "%")
        XCTAssertEqual(MetricDisplayItem.memory.unitLabel, "%")
        XCTAssertEqual(MetricDisplayItem.disk.unitLabel, "%")
    }

    func testUnitLabel_networkMetrics() {
        XCTAssertEqual(MetricDisplayItem.networkDown.unitLabel, "B/s")
        XCTAssertEqual(MetricDisplayItem.networkUp.unitLabel, "B/s")
    }

    // MARK: - rawValue(from:) returns non-negative

    func testRawValue_fromMonitor_nonNegative() {
        let monitor = SystemMonitor.shared
        for item in MetricDisplayItem.allCases {
            let raw = item.rawValue(from: monitor)
            XCTAssertGreaterThanOrEqual(raw, 0, "\(item.rawValue) should be non-negative")
        }
    }
}

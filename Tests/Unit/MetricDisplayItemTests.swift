import XCTest
@testable import TrayPulsy

final class MetricDisplayItemTests: XCTestCase {

    // MARK: - formatSpeed thresholds

    func testFormatSpeed_bytesRange() {
        let result = MetricDisplayItem.formatSpeed(500)
        XCTAssertEqual(result, " 500B")
    }

    func testFormatSpeed_exactOneK() {
        let result = MetricDisplayItem.formatSpeed(1000)
        XCTAssertEqual(result, "   1K")
    }

    func testFormatSpeed_kilobytesRange() {
        let result = MetricDisplayItem.formatSpeed(15_000)
        XCTAssertEqual(result, "  15K")
    }

    func testFormatSpeed_exactOneM() {
        let result = MetricDisplayItem.formatSpeed(1_000_000)
        XCTAssertEqual(result, " 1.0M")
    }

    func testFormatSpeed_megabytesWithDecimal() {
        let result = MetricDisplayItem.formatSpeed(1_500_000)
        XCTAssertEqual(result, " 1.5M")
    }

    func testFormatSpeed_largeMegabytes() {
        let result = MetricDisplayItem.formatSpeed(12_345_678)
        XCTAssertEqual(result, "12.3M")
    }

    func testFormatSpeed_zero() {
        let result = MetricDisplayItem.formatSpeed(0)
        XCTAssertEqual(result, "   0B")
    }

    func testFormatSpeed_lessThanOneK() {
        let result = MetricDisplayItem.formatSpeed(999)
        XCTAssertEqual(result, " 999B")
    }

    func testFormatSpeed_justBelowOneM() {
        let result = MetricDisplayItem.formatSpeed(999_999)
        XCTAssertEqual(result, "1000K")
    }

    // MARK: - formatSpeed left-padding (always 5 chars)

    func testFormatSpeed_alwaysFiveChars() {
        let cases: [Double] = [0, 1, 500, 999, 1000, 15_000, 999_999, 1_000_000, 50_000_000]
        for value in cases {
            let result = MetricDisplayItem.formatSpeed(value)
            XCTAssertEqual(result.count, 5, "formatSpeed(\(value)) produced '\(result)' — expected 5 chars")
        }
    }

    // MARK: - formatValue (percent items)

    func testFormatValue_cpu() {
        let monitor = SystemMonitor.shared
        // Just verify the format pattern: 3 chars like "17%"
        let result = MetricDisplayItem.cpu.formatValue(from: monitor)
        XCTAssertTrue(result.hasSuffix("%"), "CPU value should end with %, got: \(result)")
    }

    // MARK: - shortLabel

    func testShortLabels() {
        XCTAssertEqual(MetricDisplayItem.cpu.shortLabel, "CPU")
        XCTAssertEqual(MetricDisplayItem.gpu.shortLabel, "GPU")
        XCTAssertEqual(MetricDisplayItem.memory.shortLabel, "RAM")
        XCTAssertEqual(MetricDisplayItem.disk.shortLabel, "SSD")
        XCTAssertEqual(MetricDisplayItem.networkDown.shortLabel, "NET↓")
        XCTAssertEqual(MetricDisplayItem.networkUp.shortLabel, "NET↑")
    }

    // MARK: - displayName

    func testDisplayNames() {
        XCTAssertEqual(MetricDisplayItem.cpu.displayName, "CPU 使用率")
        XCTAssertEqual(MetricDisplayItem.gpu.displayName, "GPU 使用率")
        XCTAssertEqual(MetricDisplayItem.memory.displayName, "内存")
        XCTAssertEqual(MetricDisplayItem.disk.displayName, "磁盘")
        XCTAssertEqual(MetricDisplayItem.networkDown.displayName, "下行网速")
        XCTAssertEqual(MetricDisplayItem.networkUp.displayName, "上行网速")
    }

    // MARK: - requiredMetric

    func testRequiredMetrics() {
        XCTAssertEqual(MetricDisplayItem.cpu.requiredMetric, .cpu)
        XCTAssertEqual(MetricDisplayItem.gpu.requiredMetric, .gpu)
        XCTAssertEqual(MetricDisplayItem.memory.requiredMetric, .memory)
        XCTAssertEqual(MetricDisplayItem.disk.requiredMetric, .disk)
        XCTAssertEqual(MetricDisplayItem.networkDown.requiredMetric, .network)
        XCTAssertEqual(MetricDisplayItem.networkUp.requiredMetric, .network)
    }

    // MARK: - allCases

    func testAllCases() {
        XCTAssertEqual(MetricDisplayItem.allCases.count, 6)
    }
}

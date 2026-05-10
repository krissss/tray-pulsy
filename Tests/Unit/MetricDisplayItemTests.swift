import Defaults
import XCTest
@testable import TrayPulsy

final class MetricDisplayItemTests: XCTestCase {

    override class func setUp() {
        Defaults[.language] = .zhHans
        L10n.reload()
    }

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
        let monitor = SystemMonitor()
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

    func testSpikeKindsFromMetricItems() {
        let kinds = MetricSpikeKind.kinds(for: [.cpu, .gpu, .memory, .networkDown])

        XCTAssertEqual(kinds, [.cpu, .memory, .networkDown])
    }

    func testMonitoredChartItemsFiltersDisabledMetrics() {
        let items = MetricDisplayItem.monitoredChartItems(from: [.cpu, .memory, .networkUp])

        XCTAssertEqual(items, [.cpu, .memory, .networkUp])
        XCTAssertFalse(items.contains(.gpu))
    }

    func testMonitoredChartItemsPrefersDownloadForCombinedNetworkRow() {
        let items = MetricDisplayItem.monitoredChartItems(from: [.networkDown, .networkUp])

        XCTAssertEqual(items, [.networkDown])
    }

    func testFormattedNetworkValueShowsOnlyMonitoredDirection() {
        let monitor = SystemMonitor()

        XCTAssertEqual(
            MetricDisplayItem.networkDown.formattedValue(from: monitor, monitoredItems: [.networkDown]),
            "↓0B/s"
        )
        XCTAssertEqual(
            MetricDisplayItem.networkUp.formattedValue(from: monitor, monitoredItems: [.networkUp]),
            "↑0B/s"
        )
    }

    func testFormattedNetworkValueShowsBothDirectionsWhenBothMonitored() {
        let monitor = SystemMonitor()

        XCTAssertEqual(
            MetricDisplayItem.networkDown.formattedValue(from: monitor, monitoredItems: [.networkDown, .networkUp]),
            "↓0B/s  ↑0B/s"
        )
    }

    func testFormattedValueFallsBackWhenSnapshotDidNotRecordMetric() {
        let monitor = SystemMonitor()
        let snapshot = MetricSnapshot(
            cpuUsage: 88,
            gpuUsage: 0,
            memoryUsage: 0,
            diskUsage: 0,
            netSpeedIn: 1_200_000,
            netSpeedOut: 900_000,
            timestamp: Date(),
            recordedMetrics: [],
            recordedMetricItems: []
        )

        XCTAssertEqual(
            MetricDisplayItem.cpu.formattedValue(from: snapshot, fallback: monitor, monitoredItems: [.cpu]),
            "0%"
        )
        XCTAssertEqual(
            MetricDisplayItem.networkDown.formattedValue(
                from: snapshot,
                fallback: monitor,
                monitoredItems: [.networkDown, .networkUp]
            ),
            "↓0B/s  ↑0B/s"
        )
    }

    func testFormattedValueUsesRecordedSnapshotDirectionsIndependently() {
        let monitor = SystemMonitor()
        let snapshot = MetricSnapshot(
            cpuUsage: 0,
            gpuUsage: 0,
            memoryUsage: 0,
            diskUsage: 0,
            netSpeedIn: 1_200_000,
            netSpeedOut: 900_000,
            timestamp: Date(),
            recordedMetrics: [.network],
            recordedMetricItems: [.networkDown]
        )

        XCTAssertEqual(
            MetricDisplayItem.networkDown.formattedValue(
                from: snapshot,
                fallback: monitor,
                monitoredItems: [.networkDown, .networkUp]
            ),
            "↓1.2M/s  ↑0B/s"
        )
    }

    // MARK: - allCases

    func testAllCases() {
        XCTAssertEqual(MetricDisplayItem.allCases.count, 6)
    }
}

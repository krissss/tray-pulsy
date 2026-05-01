import Foundation
import Testing

@testable import TrayPulsy

// ═══════════════════════════════════════════════════════════════
// MARK: - MetricsHistory Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MetricsHistory")
struct MetricsHistoryTests {

    private func makeSnapshot(cpu: Double = 0, gpu: Double = 0, memory: Double = 0,
                              disk: Double = 0, netIn: Double = 0, netOut: Double = 0,
                              timestamp: Date = Date()) -> MetricSnapshot {
        MetricSnapshot(cpuUsage: cpu, gpuUsage: gpu, memoryUsage: memory,
                       diskUsage: disk, netSpeedIn: netIn, netSpeedOut: netOut,
                       timestamp: timestamp)
    }

    /// Each test gets its own temp file so no state leaks between tests.
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MetricsHistoryTests-\(UUID().uuidString).json")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Init

    @Test("Capacity is calculated from duration and interval")
    func capacityCalculation() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        #expect(h.capacity == 1800)
    }

    @Test("Capacity is clamped to [180, 7200]")
    func capacityClamped() {
        let url1 = tempURL(); defer { cleanup(url1) }
        let tiny = MetricsHistory(maxDuration: 10, sampleInterval: 1.0, storageURL: url1)
        #expect(tiny.capacity == 180)

        let url2 = tempURL(); defer { cleanup(url2) }
        let huge = MetricsHistory(maxDuration: 10000, sampleInterval: 0.5, storageURL: url2)
        #expect(huge.capacity == 7200)
    }

    @Test("Empty buffer returns empty snapshots")
    func emptyBuffer() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(storageURL: url)
        #expect(h.allSnapshots().isEmpty)
        #expect(h.snapshots(for: \.cpuUsage).isEmpty)
        #expect(h.lastSnapshot == nil)
    }

    // MARK: - record / allSnapshots

    @Test("Record and retrieve snapshots in order")
    func recordAndRetrieve() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        for i in 0..<5 {
            h.record(makeSnapshot(cpu: Double(i)))
        }
        let all = h.allSnapshots()
        #expect(all.count == 5)
        for i in 0..<5 {
            #expect(all[i].cpuUsage == Double(i))
        }
    }

    @Test("Ring wrapping overwrites oldest")
    func ringWrapping() {
        let url = tempURL(); defer { cleanup(url) }
        // Use interval=10 so cap = 1800/10 = 180
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 10.0, storageURL: url)
        let cap = h.capacity // 180
        let total = cap + 3
        for i in 0..<total {
            h.record(makeSnapshot(cpu: Double(i)))
        }
        let all = h.allSnapshots()
        #expect(all.count == cap)
        // Oldest 3 overwritten; first entry should be cpu=3
        #expect(all[0].cpuUsage == 3.0)
        #expect(all[cap - 1].cpuUsage == Double(total - 1))
    }

    @Test("lastSnapshot is always the most recent")
    func lastSnapshot() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(storageURL: url)
        h.record(makeSnapshot(cpu: 10))
        #expect(h.lastSnapshot?.cpuUsage == 10)
        h.record(makeSnapshot(cpu: 20))
        #expect(h.lastSnapshot?.cpuUsage == 20)
    }

    // MARK: - snapshots(for:)

    @Test("snapshots extracts single keypath")
    func snapshotsForKeyPath() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        h.record(makeSnapshot(cpu: 10, gpu: 50))
        h.record(makeSnapshot(cpu: 20, gpu: 60))
        h.record(makeSnapshot(cpu: 30, gpu: 70))

        #expect(h.snapshots(for: \.cpuUsage) == [10, 20, 30])
        #expect(h.snapshots(for: \.gpuUsage) == [50, 60, 70])
    }

    // MARK: - reconfigure

    @Test("Reconfigure grows buffer keeping existing data")
    func reconfigureGrow() {
        let url = tempURL(); defer { cleanup(url) }
        // Start with interval=10 → cap=180
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 10.0, storageURL: url)
        #expect(h.capacity == 180)
        for i in 0..<8 {
            h.record(makeSnapshot(cpu: Double(i)))
        }
        // Reconfigure to interval=1 → cap=1800 (grow)
        h.reconfigure(sampleInterval: 1.0)
        #expect(h.capacity == 1800)
        let all = h.allSnapshots()
        #expect(all.count == 8)
        #expect(all[0].cpuUsage == 0)
        #expect(all[7].cpuUsage == 7)
    }

    @Test("Reconfigure with same interval is no-op")
    func reconfigureSameInterval() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        h.record(makeSnapshot(cpu: 42))
        h.reconfigure(sampleInterval: 1.0)
        #expect(h.allSnapshots().count == 1)
        #expect(h.allSnapshots()[0].cpuUsage == 42)
    }

    // MARK: - clear

    @Test("Clear empties buffer but keeps capacity")
    func clearBuffer() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        for i in 0..<5 { h.record(makeSnapshot(cpu: Double(i))) }
        #expect(h.allSnapshots().count == 5)

        h.clear()
        #expect(h.allSnapshots().isEmpty)
        #expect(h.lastSnapshot == nil)
        #expect(h.capacity == 1800) // capacity preserved

        // Can record again after clear
        h.record(makeSnapshot(cpu: 99))
        #expect(h.allSnapshots().count == 1)
        #expect(h.lastSnapshot?.cpuUsage == 99)
    }

    // MARK: - Edge cases

    @Test("Minimum clamp is 180")
    func minimumCapacity() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 1, sampleInterval: 1.0, storageURL: url)
        #expect(h.capacity == 180)
    }

    @Test("Record many snapshots wraps correctly")
    func stressTest() {
        let url = tempURL(); defer { cleanup(url) }
        // interval=10 → cap=180
        let h = MetricsHistory(maxDuration: 1800, sampleInterval: 10.0, storageURL: url)
        let cap = h.capacity
        for i in 0..<500 {
            h.record(makeSnapshot(cpu: Double(i)))
        }
        #expect(h.allSnapshots().count == cap)
        #expect(h.lastSnapshot?.cpuUsage == 499)
    }

    // MARK: - Persistence

    @Test("Data persists to disk and reloads correctly")
    func persistence() {
        let url = tempURL(); defer { cleanup(url) }

        // Write some data
        let h1 = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        for i in 0..<10 {
            h1.record(makeSnapshot(cpu: Double(i)))
        }
        h1.flush()

        // Create a new instance with same file — should load the data
        let h2 = MetricsHistory(maxDuration: 1800, sampleInterval: 1.0, storageURL: url)
        let all = h2.allSnapshots()
        #expect(all.count == 10)
        #expect(all[0].cpuUsage == 0)
        #expect(all[9].cpuUsage == 9)
        #expect(h2.lastSnapshot?.cpuUsage == 9)
    }

    // MARK: - Time-based filtering

    @Test("allSnapshots filters out stale data beyond maxDuration")
    func timeFiltering() {
        let url = tempURL(); defer { cleanup(url) }
        let h = MetricsHistory(maxDuration: 600, sampleInterval: 1.0, storageURL: url) // 10 min

        let now = Date()
        // Record 3 old entries (15 min ago — beyond maxDuration)
        for i in 0..<3 {
            h.record(makeSnapshot(cpu: Double(i), timestamp: now.addingTimeInterval(-900 + Double(i))))
        }
        // Record 5 recent entries (within last 10 min)
        for i in 0..<5 {
            h.record(makeSnapshot(cpu: Double(10 + i), timestamp: now.addingTimeInterval(-300 + Double(i) * 60)))
        }

        let all = h.allSnapshots()
        #expect(all.count == 5)
        #expect(all[0].cpuUsage == 10)
        #expect(all[4].cpuUsage == 14)
    }

    @Test("Stale data on disk is not loaded")
    func staleDiskDataFiltered() {
        let url = tempURL(); defer { cleanup(url) }

        // Write data with old timestamps
        let h1 = MetricsHistory(maxDuration: 600, sampleInterval: 1.0, storageURL: url)
        let past = Date().addingTimeInterval(-7200) // 2 hours ago
        for i in 0..<5 {
            h1.record(makeSnapshot(cpu: Double(i), timestamp: past.addingTimeInterval(Double(i))))
        }
        h1.flush()

        // Load with same maxDuration — all data is stale, should get nothing
        let h2 = MetricsHistory(maxDuration: 600, sampleInterval: 1.0, storageURL: url)
        #expect(h2.allSnapshots().isEmpty)
        #expect(h2.lastSnapshot == nil)
    }

    @Test("Partial stale data on disk loads only fresh entries")
    func partialStaleDiskData() {
        let url = tempURL(); defer { cleanup(url) }
        let now = Date()

        // Write 5 old + 3 fresh entries
        let h1 = MetricsHistory(maxDuration: 600, sampleInterval: 1.0, storageURL: url)
        for i in 0..<5 {
            h1.record(makeSnapshot(cpu: Double(i), timestamp: now.addingTimeInterval(-900))) // 15 min ago
        }
        for i in 0..<3 {
            h1.record(makeSnapshot(cpu: Double(100 + i), timestamp: now.addingTimeInterval(-60 * Double(i))))
        }
        h1.flush()

        // Reload — only the 3 fresh entries should survive
        let h2 = MetricsHistory(maxDuration: 600, sampleInterval: 1.0, storageURL: url)
        let all = h2.allSnapshots()
        #expect(all.count == 3)
        #expect(all[0].cpuUsage == 102) // oldest fresh (3 min ago)
        #expect(all[2].cpuUsage == 100) // newest fresh (now)
    }

    @Test("Binary plist round-trip preserves all fields")
    func binaryPlistRoundTrip() {
        let original = MetricSnapshot(
            cpuUsage: 42.5, gpuUsage: 15.3, memoryUsage: 67.8,
            diskUsage: 23.1, netSpeedIn: 1_500_000, netSpeedOut: 250_000,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoded = try! PropertyListEncoder().encode([original])
        let decoded = try! PropertyListDecoder().decode([MetricSnapshot].self, from: encoded)

        #expect(decoded.count == 1)
        #expect(decoded[0].cpuUsage == 42.5)
        #expect(decoded[0].gpuUsage == 15.3)
        #expect(decoded[0].memoryUsage == 67.8)
        #expect(decoded[0].diskUsage == 23.1)
        #expect(decoded[0].netSpeedIn == 1_500_000)
        #expect(decoded[0].netSpeedOut == 250_000)
        #expect(decoded[0].timestamp.timeIntervalSince1970 == 1_700_000_000)
    }
}

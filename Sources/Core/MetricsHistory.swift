import Foundation

/// A single point-in-time snapshot of all system metrics.
struct MetricSnapshot: Codable {
    let cpuUsage: Double
    let gpuUsage: Double
    let memoryUsage: Double
    let diskUsage: Double
    let netSpeedIn: Double
    let netSpeedOut: Double
    let timestamp: Date
    let recordedMetrics: Set<SystemMonitor.MetricKind>
    let recordedMetricItems: Set<MetricDisplayItem>

    init(
        cpuUsage: Double,
        gpuUsage: Double,
        memoryUsage: Double,
        diskUsage: Double,
        netSpeedIn: Double,
        netSpeedOut: Double,
        timestamp: Date,
        recordedMetrics: Set<SystemMonitor.MetricKind> = Set(SystemMonitor.MetricKind.allCases),
        recordedMetricItems: Set<MetricDisplayItem>? = nil
    ) {
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.netSpeedIn = netSpeedIn
        self.netSpeedOut = netSpeedOut
        self.timestamp = timestamp
        self.recordedMetrics = recordedMetrics
        self.recordedMetricItems = recordedMetricItems ?? MetricDisplayItem.items(for: recordedMetrics)
    }

    private enum CodingKeys: String, CodingKey {
        case cpuUsage
        case gpuUsage
        case memoryUsage
        case diskUsage
        case netSpeedIn
        case netSpeedOut
        case timestamp
        case recordedMetrics
        case recordedMetricItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpuUsage = try container.decode(Double.self, forKey: .cpuUsage)
        gpuUsage = try container.decode(Double.self, forKey: .gpuUsage)
        memoryUsage = try container.decode(Double.self, forKey: .memoryUsage)
        diskUsage = try container.decode(Double.self, forKey: .diskUsage)
        netSpeedIn = try container.decode(Double.self, forKey: .netSpeedIn)
        netSpeedOut = try container.decode(Double.self, forKey: .netSpeedOut)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let decodedMetrics = try container.decodeIfPresent(
            Set<SystemMonitor.MetricKind>.self,
            forKey: .recordedMetrics
        ) ?? Set(SystemMonitor.MetricKind.allCases)
        recordedMetrics = decodedMetrics
        let decodedItems = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .recordedMetricItems
        )
        recordedMetricItems = decodedItems.map { rawItems in
            Set(rawItems.compactMap(MetricDisplayItem.init(rawValue:)))
        } ?? MetricDisplayItem.items(for: decodedMetrics)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cpuUsage, forKey: .cpuUsage)
        try container.encode(gpuUsage, forKey: .gpuUsage)
        try container.encode(memoryUsage, forKey: .memoryUsage)
        try container.encode(diskUsage, forKey: .diskUsage)
        try container.encode(netSpeedIn, forKey: .netSpeedIn)
        try container.encode(netSpeedOut, forKey: .netSpeedOut)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(recordedMetrics, forKey: .recordedMetrics)
        try container.encode(Set(recordedMetricItems.map(\.rawValue)), forKey: .recordedMetricItems)
    }

    func records(_ metric: SystemMonitor.MetricKind) -> Bool {
        recordedMetrics.contains(metric)
    }

    func records(_ item: MetricDisplayItem) -> Bool {
        recordedMetricItems.contains(item)
    }
}

/// Fixed-capacity ring buffer that stores up to `maxDuration / sampleInterval` snapshots.
///
/// Data is persisted to disk as a binary plist file in Application Support.
/// The file is only written on `flush()` (app exit / sleep), not periodically.
@Observable
final class MetricsHistory: @unchecked Sendable {

    private var buffer: [MetricSnapshot]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private(set) var capacity: Int
    private var maxDuration: TimeInterval

    /// Most recent snapshot (for carry-forward when a metric is disabled).
    private(set) var lastSnapshot: MetricSnapshot?

    /// Cached result of `allSnapshots()`, invalidated on `record()` / `clear()`.
    private var cachedSnapshots: [MetricSnapshot]?
    /// Pre-extracted per-metric arrays, built once alongside cachedSnapshots.
    private var cachedTimestamps: [Date] = []
    private var cachedCPU: [Double] = []
    private var cachedGPU: [Double] = []
    private var cachedMemory: [Double] = []
    private var cachedDisk: [Double] = []
    private var cachedNetIn: [Double] = []
    private var cachedNetOut: [Double] = []
    private var cachedCPUTimestamps: [Date] = []
    private var cachedGPUTimestamps: [Date] = []
    private var cachedMemoryTimestamps: [Date] = []
    private var cachedDiskTimestamps: [Date] = []
    private var cachedNetInTimestamps: [Date] = []
    private var cachedNetOutTimestamps: [Date] = []

    // MARK: - Persistence

    private let fileURL: URL

    // MARK: - Init

    init(maxDuration: TimeInterval = 1800, sampleInterval: TimeInterval = 1.0, storageURL: URL? = nil) {
        let cap = max(180, min(7200, Int(maxDuration / max(sampleInterval, 0.01))))
        self.capacity = cap
        self.maxDuration = maxDuration

        // Resolve persistence path
        if let storageURL {
            self.fileURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("TrayPulsy", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("metrics_history.bin")
        }

        // Init buffer and load from disk (stale data is pruned by maxDuration)
        var buf = [MetricSnapshot]()
        buf.reserveCapacity(cap)
        Self.loadFromDisk(into: &buf, capacity: cap, maxDuration: maxDuration, url: fileURL)
        self.buffer = buf

        // Reconstruct ring buffer indices from loaded data
        if buffer.count > cap {
            buffer = Array(buffer.suffix(cap))
        }
        writeIndex = buffer.count % cap
        count = buffer.count
        if let last = buffer.last {
            lastSnapshot = last
        }
    }

    deinit {
        saveSync()
    }

    // MARK: - Record

    /// Append a snapshot. If the buffer is full, the oldest entry is overwritten.
    func record(_ snapshot: MetricSnapshot) {
        lastSnapshot = snapshot
        if buffer.count < capacity {
            buffer.append(snapshot)
        } else {
            buffer[writeIndex] = snapshot
        }
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
        cachedSnapshots = nil // invalidate cache
    }

    // MARK: - Query

    /// All snapshots within `maxDuration`, ordered oldest-to-newest.
    /// Result is cached until the next `record()` or `clear()`.
    func allSnapshots() -> [MetricSnapshot] {
        if let cached = cachedSnapshots { return cached }
        guard count > 0 else { return [] }
        let raw: [MetricSnapshot]
        if count < capacity {
            raw = Array(buffer.prefix(count))
        } else {
            raw = Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
        }
        let cutoff = Date().addingTimeInterval(-maxDuration)
        let result = raw.filter { $0.timestamp >= cutoff }
        // Build pre-extracted per-metric arrays
        cachedTimestamps = result.map(\.timestamp)
        let cpuSnapshots = result.filter { $0.records(MetricDisplayItem.cpu) }
        let gpuSnapshots = result.filter { $0.records(MetricDisplayItem.gpu) }
        let memorySnapshots = result.filter { $0.records(MetricDisplayItem.memory) }
        let diskSnapshots = result.filter { $0.records(MetricDisplayItem.disk) }
        let networkInSnapshots = result.filter { $0.records(MetricDisplayItem.networkDown) }
        let networkOutSnapshots = result.filter { $0.records(MetricDisplayItem.networkUp) }

        cachedCPU = cpuSnapshots.map(\.cpuUsage)
        cachedGPU = gpuSnapshots.map(\.gpuUsage)
        cachedMemory = memorySnapshots.map(\.memoryUsage)
        cachedDisk = diskSnapshots.map(\.diskUsage)
        cachedNetIn = networkInSnapshots.map(\.netSpeedIn)
        cachedNetOut = networkOutSnapshots.map(\.netSpeedOut)
        cachedCPUTimestamps = cpuSnapshots.map(\.timestamp)
        cachedGPUTimestamps = gpuSnapshots.map(\.timestamp)
        cachedMemoryTimestamps = memorySnapshots.map(\.timestamp)
        cachedDiskTimestamps = diskSnapshots.map(\.timestamp)
        cachedNetInTimestamps = networkInSnapshots.map(\.timestamp)
        cachedNetOutTimestamps = networkOutSnapshots.map(\.timestamp)
        cachedSnapshots = result
        return result
    }

    /// Extract a single metric's values as Doubles, oldest-to-newest.
    /// Uses pre-extracted cached arrays when available.
    func snapshots(for keyPath: KeyPath<MetricSnapshot, Double>) -> [Double] {
        ensureCacheWarm()
        return cachedValues(for: keyPath)
    }

    /// Return the pre-extracted cached array for a given metric keyPath.
    /// Self-warming: populates cache on first call if needed.
    func cachedValues(for keyPath: KeyPath<MetricSnapshot, Double>) -> [Double] {
        ensureCacheWarm()
        switch keyPath {
        case \.cpuUsage:     return cachedCPU
        case \.gpuUsage:     return cachedGPU
        case \.memoryUsage:  return cachedMemory
        case \.diskUsage:    return cachedDisk
        case \.netSpeedIn:   return cachedNetIn
        case \.netSpeedOut:  return cachedNetOut
        default:             return []
        }
    }

    /// Return the pre-extracted timestamps array. Self-warming.
    func cachedTimestampArray() -> [Date] {
        ensureCacheWarm()
        return cachedTimestamps
    }

    func cachedTimestampArray(for keyPath: KeyPath<MetricSnapshot, Double>) -> [Date] {
        ensureCacheWarm()
        switch keyPath {
        case \.cpuUsage:     return cachedCPUTimestamps
        case \.gpuUsage:     return cachedGPUTimestamps
        case \.memoryUsage:  return cachedMemoryTimestamps
        case \.diskUsage:    return cachedDiskTimestamps
        case \.netSpeedIn:   return cachedNetInTimestamps
        case \.netSpeedOut:  return cachedNetOutTimestamps
        default:             return []
        }
    }

    /// Ensure the per-metric cache arrays are populated.
    private func ensureCacheWarm() {
        if cachedSnapshots == nil { _ = allSnapshots() }
    }

    // MARK: - Reconfigure

    /// Resize the buffer when the sample interval or max duration changes. Existing data is preserved (newest kept).
    func reconfigure(maxDuration: TimeInterval = 1800, sampleInterval: TimeInterval) {
        let newCap = max(180, min(7200, Int(maxDuration / max(sampleInterval, 0.01))))
        self.maxDuration = maxDuration
        guard newCap != capacity else { return }
        capacity = newCap
        let old = allSnapshots()
        buffer = [MetricSnapshot]()
        buffer.reserveCapacity(newCap)
        // Keep the most recent `newCap` entries
        let keep = Array(old.suffix(newCap))
        for s in keep { buffer.append(s) }
        writeIndex = buffer.count % newCap
        count = buffer.count
        clearCaches()
    }

    func clear() {
        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        count = 0
        lastSnapshot = nil
        clearCaches()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func clearCaches() {
        cachedSnapshots = nil
        cachedTimestamps = []
        cachedCPU = []
        cachedGPU = []
        cachedMemory = []
        cachedDisk = []
        cachedNetIn = []
        cachedNetOut = []
        cachedCPUTimestamps = []
        cachedGPUTimestamps = []
        cachedMemoryTimestamps = []
        cachedDiskTimestamps = []
        cachedNetInTimestamps = []
        cachedNetOutTimestamps = []
    }

    /// Write data to disk. Call on app termination / sleep.
    func flush() {
        saveSync()
    }

    // MARK: - Persistence (private)

    private nonisolated func saveSync() {
        let data: [MetricSnapshot]
        if count < capacity {
            data = Array(buffer.prefix(count))
        } else if count > 0 {
            data = Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
        } else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        // Prune stale entries
        let cutoff = Date().addingTimeInterval(-maxDuration)
        let fresh = data.filter { $0.timestamp >= cutoff }
        guard !fresh.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let encoded = try encoder.encode(fresh)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            // Best effort
        }
    }

    /// Load snapshots from disk, discarding entries older than `maxDuration`.
    private static func loadFromDisk(into buffer: inout [MetricSnapshot], capacity: Int, maxDuration: TimeInterval, url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let loaded = try? PropertyListDecoder().decode([MetricSnapshot].self, from: data) else { return }

        // Discard stale entries, sort by timestamp, keep the most recent `capacity`
        let cutoff = Date().addingTimeInterval(-maxDuration)
        let fresh = loaded
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
        buffer = Array(fresh.suffix(capacity))
    }
}

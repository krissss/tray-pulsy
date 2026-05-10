import Foundation
import Darwin
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Metric Spike Diagnostics
// ═══════════════════════════════════════════════════════════════

enum MetricSpikeKind: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case networkDown
    case networkUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu:         return L10n.metricOverviewCpu
        case .memory:      return L10n.metricOverviewMemory
        case .networkDown: return L10n.metricNetDown
        case .networkUp:   return L10n.metricNetUp
        }
    }

    var systemImage: String {
        switch self {
        case .cpu:         return "cpu"
        case .memory:      return "memorychip"
        case .networkDown: return "arrow.down.circle"
        case .networkUp:   return "arrow.up.circle"
        }
    }

    var accentColor: Color {
        switch self {
        case .cpu:         return .blue
        case .memory:      return .orange
        case .networkDown: return .purple
        case .networkUp:   return .purple
        }
    }

    func value(from snapshot: MetricSnapshot) -> Double {
        switch self {
        case .cpu:         return snapshot.cpuUsage
        case .memory:      return snapshot.memoryUsage
        case .networkDown: return snapshot.netSpeedIn
        case .networkUp:   return snapshot.netSpeedOut
        }
    }

    var requiredMetric: SystemMonitor.MetricKind {
        switch self {
        case .cpu:         return .cpu
        case .memory:      return .memory
        case .networkDown,
             .networkUp:   return .network
        }
    }

    var requiredMetricItem: MetricDisplayItem {
        switch self {
        case .cpu:         return .cpu
        case .memory:      return .memory
        case .networkDown: return .networkDown
        case .networkUp:   return .networkUp
        }
    }

    func isMonitored(in metricItems: Set<MetricDisplayItem>) -> Bool {
        metricItems.contains(requiredMetricItem)
    }

    static func kinds(for metricItems: Set<MetricDisplayItem>) -> Set<MetricSpikeKind> {
        var kinds = Set<MetricSpikeKind>()
        if metricItems.contains(.cpu) {
            kinds.insert(.cpu)
        }
        if metricItems.contains(.memory) {
            kinds.insert(.memory)
        }
        if metricItems.contains(.networkDown) {
            kinds.insert(.networkDown)
        }
        if metricItems.contains(.networkUp) {
            kinds.insert(.networkUp)
        }
        return kinds
    }

    func thresholds(from config: ThresholdConfig) -> MetricThresholds {
        switch self {
        case .cpu:         return config.cpu
        case .memory:      return config.memory
        case .networkDown: return config.networkDown
        case .networkUp:   return config.networkUp
        }
    }

    func formatValue(_ value: Double) -> String {
        switch self {
        case .cpu, .memory:
            return String(format: "%.1f%%", value)
        case .networkDown, .networkUp:
            return MetricDisplayItem.formatSpeed(value).trimmingCharacters(in: .whitespaces) + "/s"
        }
    }

    func rule(for config: ThresholdConfig) -> MetricSpikeRule {
        let metricThresholds = thresholds(from: config)
        switch self {
        case .cpu:
            return MetricSpikeRule(minimumValue: max(50, metricThresholds.warning), minimumDelta: 25)
        case .memory:
            return MetricSpikeRule(minimumValue: max(65, metricThresholds.warning), minimumDelta: 8)
        case .networkDown:
            return MetricSpikeRule(
                minimumValue: metricThresholds.warning,
                minimumDelta: max(500_000, metricThresholds.warning * 0.5)
            )
        case .networkUp:
            return MetricSpikeRule(
                minimumValue: metricThresholds.warning,
                minimumDelta: max(250_000, metricThresholds.warning * 0.5)
            )
        }
    }

    func rule(for thresholdConfig: ThresholdConfig, spikeDeltaConfig: SpikeDeltaConfig) -> MetricSpikeRule {
        let base = rule(for: thresholdConfig)
        let configuredDelta: Double
        switch self {
        case .cpu:
            configuredDelta = spikeDeltaConfig.cpu
        case .memory:
            configuredDelta = spikeDeltaConfig.memory
        case .networkDown:
            configuredDelta = spikeDeltaConfig.networkDown
        case .networkUp:
            configuredDelta = spikeDeltaConfig.networkUp
        }
        return MetricSpikeRule(minimumValue: base.minimumValue, minimumDelta: max(0, configuredDelta))
    }
}

extension MetricSpikeKind: Codable {}

struct MetricSpikeRule: Equatable, Sendable {
    let minimumValue: Double
    let minimumDelta: Double
}

struct MetricSpikeCandidate: Equatable, Sendable {
    let metric: MetricSpikeKind
    let previousValue: Double
    let currentValue: Double
    let delta: Double
    let timestamp: Date
    let score: Double
}

enum SpikeProcessMetric: String, Sendable {
    case cpu
    case memory
    case network
}

extension SpikeProcessMetric: Codable {}

struct SpikeProcessSnapshot: Identifiable, Equatable, Codable, Sendable {
    let pid: Int
    let name: String
    let valueText: String
    let fraction: Double
    let metric: SpikeProcessMetric

    var id: String { "\(metric.rawValue)-\(pid)" }
}

enum SpikeProcessSampleStatus: Equatable, Codable, Sendable {
    case sampling
    case ready
    case unavailable
    case failed(String)

    var isSampling: Bool {
        if case .sampling = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var persistable: SpikeProcessSampleStatus {
        isSampling ? .unavailable : self
    }
}

struct MetricSpikeEvent: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let metric: MetricSpikeKind
    let previousValue: Double
    let currentValue: Double
    let delta: Double
    let timestamp: Date
    var processStatus: SpikeProcessSampleStatus
    var processes: [SpikeProcessSnapshot]

    init(id: UUID = UUID(), candidate: MetricSpikeCandidate) {
        self.id = id
        self.metric = candidate.metric
        self.previousValue = candidate.previousValue
        self.currentValue = candidate.currentValue
        self.delta = candidate.delta
        self.timestamp = candidate.timestamp
        self.processStatus = .sampling
        self.processes = []
    }

    init(
        id: UUID,
        metric: MetricSpikeKind,
        previousValue: Double,
        currentValue: Double,
        delta: Double,
        timestamp: Date,
        processStatus: SpikeProcessSampleStatus,
        processes: [SpikeProcessSnapshot]
    ) {
        self.id = id
        self.metric = metric
        self.previousValue = previousValue
        self.currentValue = currentValue
        self.delta = delta
        self.timestamp = timestamp
        self.processStatus = processStatus
        self.processes = processes
    }
}

/// Fixed-size spike event buffer persisted like MetricsHistory: loaded on init,
/// written only on flush (app exit / sleep), never periodically.
@Observable
final class MetricSpikeHistory: @unchecked Sendable {
    private(set) var events: [MetricSpikeEvent] = []
    private var limit: Int
    private let fileURL: URL

    init(limit: Int = 12, storageURL: URL? = nil) {
        self.limit = max(0, limit)
        if let storageURL {
            self.fileURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("TrayPulsy", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("spike_events.bin")
        }
        events = Self.loadFromDisk(limit: self.limit, url: fileURL)
    }

    deinit {
        saveSync()
    }

    func record(_ event: MetricSpikeEvent) {
        guard limit > 0 else { return }
        events.insert(event, at: 0)
        trimToLimit()
    }

    func replace(_ updated: MetricSpikeEvent) {
        guard let index = events.firstIndex(where: { $0.id == updated.id }) else { return }
        events[index] = updated
        trimToLimit()
    }

    func clear() {
        events.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func reconfigure(limit newLimit: Int) {
        limit = max(0, newLimit)
        trimToLimit()
    }

    func flush() {
        saveSync()
    }

    private func trimToLimit() {
        if events.count > limit {
            events = Array(events.prefix(limit))
        }
    }

    private nonisolated func saveSync() {
        let data = Array(events.prefix(limit)).map { event in
            MetricSpikeEvent(
                id: event.id,
                metric: event.metric,
                previousValue: event.previousValue,
                currentValue: event.currentValue,
                delta: event.delta,
                timestamp: event.timestamp,
                processStatus: event.processStatus.persistable,
                processes: event.processes
            )
        }
        guard !data.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            // Best effort
        }
    }

    private static func loadFromDisk(limit: Int, url: URL) -> [MetricSpikeEvent] {
        guard limit > 0 else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let loaded = try? PropertyListDecoder().decode([MetricSpikeEvent].self, from: data) else { return [] }

        let restored = loaded.map { event in
            MetricSpikeEvent(
                id: event.id,
                metric: event.metric,
                previousValue: event.previousValue,
                currentValue: event.currentValue,
                delta: event.delta,
                timestamp: event.timestamp,
                processStatus: event.processStatus.persistable,
                processes: event.processes
            )
        }
        .sorted { $0.timestamp > $1.timestamp }

        return Array(restored.prefix(limit))
    }
}

struct MetricSpikeDetector {
    var cooldown: TimeInterval = 30

    private var previousSnapshot: MetricSnapshot?
    private var lastSpikeDates: [MetricSpikeKind: Date] = [:]

    mutating func detect(
        snapshot: MetricSnapshot,
        thresholds: ThresholdConfig,
        spikeDeltas: SpikeDeltaConfig = .defaults,
        now: Date = Date(),
        includedMetrics: Set<MetricSpikeKind> = Set(MetricSpikeKind.allCases),
        excludedMetrics: Set<MetricSpikeKind> = [],
        shouldRecordCooldown: Bool = true
    ) -> MetricSpikeCandidate? {
        let candidates = detectCandidates(
            snapshot: snapshot,
            thresholds: thresholds,
            spikeDeltas: spikeDeltas,
            now: now,
            includedMetrics: includedMetrics,
            excludedMetrics: excludedMetrics,
            shouldRecordCooldown: false
        )

        guard let best = candidates.first else { return nil }
        if shouldRecordCooldown {
            recordCooldown(for: best.metric, at: now)
        }
        return best
    }

    mutating func detectCandidates(
        snapshot: MetricSnapshot,
        thresholds: ThresholdConfig,
        spikeDeltas: SpikeDeltaConfig = .defaults,
        now: Date = Date(),
        includedMetrics: Set<MetricSpikeKind> = Set(MetricSpikeKind.allCases),
        excludedMetrics: Set<MetricSpikeKind> = [],
        shouldRecordCooldown: Bool = true,
        preserveCandidateBaselines: Bool = false
    ) -> [MetricSpikeCandidate] {
        guard let previousSnapshot else {
            advancePreviousSnapshot(to: snapshot, preserving: [])
            return []
        }

        let candidates = MetricSpikeKind.allCases.compactMap { kind -> MetricSpikeCandidate? in
            guard includedMetrics.contains(kind) else { return nil }
            guard !excludedMetrics.contains(kind) else { return nil }
            guard canRecord(kind, at: now) else { return nil }
            guard previousSnapshot.records(kind.requiredMetricItem), snapshot.records(kind.requiredMetricItem) else {
                return nil
            }

            let previousValue = kind.value(from: previousSnapshot)
            let currentValue = kind.value(from: snapshot)
            let delta = currentValue - previousValue
            let rule = kind.rule(for: thresholds, spikeDeltaConfig: spikeDeltas)

            guard currentValue >= rule.minimumValue, delta >= rule.minimumDelta else { return nil }

            let valueScore = currentValue / max(rule.minimumValue, 1)
            let deltaScore = delta / max(rule.minimumDelta, 1)
            return MetricSpikeCandidate(
                metric: kind,
                previousValue: previousValue,
                currentValue: currentValue,
                delta: delta,
                timestamp: snapshot.timestamp,
                score: valueScore + deltaScore
            )
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.metric.rawValue < rhs.metric.rawValue
        }
        if shouldRecordCooldown {
            sorted.forEach { recordCooldown(for: $0.metric, at: now) }
        }
        let candidateMetrics = preserveCandidateBaselines
            ? Set(sorted.map(\.metric))
            : []
        advancePreviousSnapshot(to: snapshot, preserving: excludedMetrics.union(candidateMetrics))
        return sorted
    }

    private mutating func advancePreviousSnapshot(
        to snapshot: MetricSnapshot,
        preserving preservedMetrics: Set<MetricSpikeKind>
    ) {
        guard let baseline = previousSnapshot, !preservedMetrics.isEmpty else {
            previousSnapshot = snapshot
            return
        }

        previousSnapshot = MetricSnapshot(
            cpuUsage: preservedMetrics.contains(.cpu) ? baseline.cpuUsage : snapshot.cpuUsage,
            gpuUsage: snapshot.gpuUsage,
            memoryUsage: preservedMetrics.contains(.memory) ? baseline.memoryUsage : snapshot.memoryUsage,
            diskUsage: snapshot.diskUsage,
            netSpeedIn: preservedMetrics.contains(.networkDown) ? baseline.netSpeedIn : snapshot.netSpeedIn,
            netSpeedOut: preservedMetrics.contains(.networkUp) ? baseline.netSpeedOut : snapshot.netSpeedOut,
            timestamp: snapshot.timestamp,
            recordedMetrics: recordedMetrics(
                baseline: baseline,
                snapshot: snapshot,
                preserving: preservedMetrics
            ),
            recordedMetricItems: recordedMetricItems(
                baseline: baseline,
                snapshot: snapshot,
                preserving: preservedMetrics
            )
        )
    }

    private func recordedMetrics(
        baseline: MetricSnapshot,
        snapshot: MetricSnapshot,
        preserving preservedMetrics: Set<MetricSpikeKind>
    ) -> Set<SystemMonitor.MetricKind> {
        var metrics = snapshot.recordedMetrics
        if preservedMetrics.contains(.cpu), baseline.records(SystemMonitor.MetricKind.cpu) {
            metrics.insert(.cpu)
        }
        if preservedMetrics.contains(.memory), baseline.records(SystemMonitor.MetricKind.memory) {
            metrics.insert(.memory)
        }
        if (preservedMetrics.contains(.networkDown) || preservedMetrics.contains(.networkUp)),
           baseline.records(.network) {
            metrics.insert(.network)
        }
        return metrics
    }

    private func recordedMetricItems(
        baseline: MetricSnapshot,
        snapshot: MetricSnapshot,
        preserving preservedMetrics: Set<MetricSpikeKind>
    ) -> Set<MetricDisplayItem> {
        var items = snapshot.recordedMetricItems
        for metric in preservedMetrics where baseline.records(metric.requiredMetricItem) {
            items.insert(metric.requiredMetricItem)
        }
        return items
    }

    mutating func reset() {
        previousSnapshot = nil
        lastSpikeDates.removeAll()
    }

    mutating func clearCooldown(for kind: MetricSpikeKind) {
        lastSpikeDates.removeValue(forKey: kind)
    }

    mutating func recordCooldown(for kind: MetricSpikeKind, at now: Date = Date()) {
        lastSpikeDates[kind] = now
    }

    private func canRecord(_ kind: MetricSpikeKind, at now: Date) -> Bool {
        guard let lastDate = lastSpikeDates[kind] else { return true }
        return now.timeIntervalSince(lastDate) >= cooldown
    }
}

struct MetricSpikeConfirmation: Equatable, Sendable {
    let candidate: MetricSpikeCandidate
    let processes: [SpikeProcessSnapshot]
}

private struct MetricSpikeSample: Sendable {
    let value: Double
    let timestamp: Date
    let processes: [SpikeProcessSnapshot]
}

enum MetricSpikeConfirmationError: LocalizedError {
    case cpuCountersUnavailable
    case memoryStatsUnavailable
    case networkCountersUnavailable

    var errorDescription: String? {
        switch self {
        case .cpuCountersUnavailable:
            return "CPU counters unavailable"
        case .memoryStatsUnavailable:
            return "memory stats unavailable"
        case .networkCountersUnavailable:
            return "network counters unavailable"
        }
    }
}

private enum SystemMetricReader {
    private static let bytesPerGB: Double = 1024 * 1024 * 1024

    struct CPUTicks: Sendable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
        let timestamp: Date
    }

    struct NetworkCounters: Sendable {
        let inBytes: UInt64
        let outBytes: UInt64
        let timestamp: Date
    }

    static func readCPUTicks() throws -> CPUTicks {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricSpikeConfirmationError.cpuCountersUnavailable
        }
        return CPUTicks(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3),
            timestamp: Date()
        )
    }

    static func cpuUsage(from first: CPUTicks, to second: CPUTicks) -> Double {
        let dU = second.user >= first.user ? second.user - first.user : 0
        let dS = second.system >= first.system ? second.system - first.system : 0
        let dI = second.idle >= first.idle ? second.idle - first.idle : 0
        let dN = second.nice >= first.nice ? second.nice - first.nice : 0
        let total = dU + dS + dI + dN
        guard total > 0 else { return 0 }
        return min(100, Double(dU + dS + dN) / Double(total) * 100)
    }

    static func readMemoryUsage() throws -> Double {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricSpikeConfirmationError.memoryStatsUnavailable
        }

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let page = Double(pageSize > 0 ? pageSize : 4096)
        let free = Double(stats.free_count) * page
        let purgeable = Double(stats.purgeable_count) * page
        let external = Double(stats.external_page_count) * page
        let used = total - free - purgeable - external
        guard total > 0 else { return 0 }
        return min(100, max(0, used / total * 100))
    }

    static func readNetworkCounters() throws -> NetworkCounters {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            throw MetricSpikeConfirmationError.networkCountersUnavailable
        }
        defer { freeifaddrs(ifaddr) }

        var iface: UnsafeMutablePointer<ifaddrs>? = first
        while let current = iface {
            guard let namePtr = current.pointee.ifa_name else {
                iface = current.pointee.ifa_next
                continue
            }

            let b0 = namePtr.pointee
            let b1 = (namePtr + 1).pointee
            let isEN = b0 == UInt8(ascii: "e") && b1 == UInt8(ascii: "n")
            let isBridge = b0 == UInt8(ascii: "b") && b1 == UInt8(ascii: "r")
            guard isEN || isBridge else {
                iface = current.pointee.ifa_next
                continue
            }

            if let addr = current.pointee.ifa_addr,
               Int32(addr.pointee.sa_family) == AF_LINK,
               let data = current.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(ifData.ifi_ibytes)
                totalOut += UInt64(ifData.ifi_obytes)
            }
            iface = current.pointee.ifa_next
        }

        return NetworkCounters(inBytes: totalIn, outBytes: totalOut, timestamp: Date())
    }

    static func networkSpeed(
        metric: MetricSpikeKind,
        from first: NetworkCounters,
        to second: NetworkCounters
    ) -> Double {
        let elapsed = max(second.timestamp.timeIntervalSince(first.timestamp), 0.01)
        switch metric {
        case .networkUp:
            let delta = second.outBytes >= first.outBytes ? second.outBytes - first.outBytes : 0
            return Double(delta) / elapsed
        default:
            let delta = second.inBytes >= first.inBytes ? second.inBytes - first.inBytes : 0
            return Double(delta) / elapsed
        }
    }
}

enum MetricSpikeProcessSampler {
    static func confirmSpike(
        candidate: MetricSpikeCandidate,
        thresholds: ThresholdConfig,
        spikeDeltas: SpikeDeltaConfig,
        limit: Int = 5
    ) async -> Result<MetricSpikeConfirmation?, Error> {
        let cancellationContext = ProcessCancellationContext()
        let worker = Task.detached(priority: .utility) { () -> Result<MetricSpikeConfirmation?, Error> in
            do {
                try Task.checkCancellation()
                let sample = try await sample(
                    metric: candidate.metric,
                    limit: limit,
                    cancellationContext: cancellationContext
                )
                try Task.checkCancellation()
                guard let confirmation = confirmedSpike(
                    original: candidate,
                    sample: sample,
                    thresholds: thresholds,
                    spikeDeltas: spikeDeltas
                ) else {
                    return .success(nil)
                }
                return .success(confirmation)
            } catch {
                return .failure(error)
            }
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            cancellationContext.cancel()
            worker.cancel()
        }
    }

    static func confirmedNetworkSpike(
        candidate: MetricSpikeCandidate,
        current: ProcessNetworkSampleFrame,
        baseline: ProcessNetworkSampleFrame,
        thresholds: ThresholdConfig,
        spikeDeltas: SpikeDeltaConfig,
        limit: Int = 5
    ) -> MetricSpikeConfirmation? {
        let sortMode: ProcessNetworkSortMode = candidate.metric == .networkUp ? .upload : .download
        let sample = networkSample(
            current: Array(current.samplesByPID.values),
            previous: baseline.samplesByPID,
            elapsed: current.timestamp.timeIntervalSince(baseline.timestamp),
            timestamp: current.timestamp,
            metric: candidate.metric,
            limit: limit,
            sortMode: sortMode
        )
        return confirmedSpike(
            original: candidate,
            sample: sample,
            thresholds: thresholds,
            spikeDeltas: spikeDeltas
        )
    }

    static func confirmedSpike(
        candidate: MetricSpikeCandidate,
        currentValue: Double,
        timestamp: Date,
        processes: [SpikeProcessSnapshot],
        thresholds: ThresholdConfig,
        spikeDeltas: SpikeDeltaConfig
    ) -> MetricSpikeConfirmation? {
        confirmedSpike(
            original: candidate,
            sample: MetricSpikeSample(value: currentValue, timestamp: timestamp, processes: processes),
            thresholds: thresholds,
            spikeDeltas: spikeDeltas
        )
    }

    private static func resourceSnapshots(
        _ samples: [ProcessResourceUsage],
        kind: ProcessResourceKind,
        limit: Int
    ) -> [SpikeProcessSnapshot] {
        ProcessResourceReader.topProcesses(samples, kind: kind, limit: limit).map { process in
            switch kind {
            case .cpu:
                return SpikeProcessSnapshot(
                    pid: process.pid,
                    name: process.name,
                    valueText: String(format: "%.1f%%", process.cpuPercent),
                    fraction: min(max(process.cpuPercent / 100, 0), 1),
                    metric: .cpu
                )
            case .memory:
                let formatter = ByteCountFormatter()
                formatter.countStyle = .memory
                formatter.allowedUnits = [.useMB, .useGB]
                return SpikeProcessSnapshot(
                    pid: process.pid,
                    name: process.name,
                    valueText: "\(formatter.string(fromByteCount: process.memoryBytes)) \(String(format: "%.1f%%", process.memoryPercent))",
                    fraction: min(max(process.memoryPercent / 100, 0), 1),
                    metric: .memory
                )
            }
        }
    }

    private static func sample(
        metric: MetricSpikeKind,
        limit: Int,
        cancellationContext: ProcessCancellationContext
    ) async throws -> MetricSpikeSample {
        switch metric {
        case .cpu:
            return try await cpuSample(limit: limit, cancellationContext: cancellationContext)
        case .memory:
            return try memorySample(limit: limit, cancellationContext: cancellationContext)
        case .networkDown, .networkUp:
            return try await networkSample(metric: metric, limit: limit, cancellationContext: cancellationContext)
        }
    }

    private static func cpuSample(
        limit: Int,
        cancellationContext: ProcessCancellationContext
    ) async throws -> MetricSpikeSample {
        let firstTicks = try SystemMetricReader.readCPUTicks()
        let firstProcesses = try ProcessResourceReader.readSampleFrame(cancellationContext: cancellationContext)
        try Task.checkCancellation()
        try cancellationContext.checkCancellation()
        try await Task.sleep(for: .milliseconds(350))
        try Task.checkCancellation()
        try cancellationContext.checkCancellation()
        let secondProcesses = try ProcessResourceReader.readSampleFrame(cancellationContext: cancellationContext)
        let secondTicks = try SystemMetricReader.readCPUTicks()
        let elapsed = max(secondProcesses.timestamp.timeIntervalSince(firstProcesses.timestamp), 0.01)
        let active = ProcessResourceReader.activeCPUProcesses(
            current: secondProcesses.samples,
            previous: firstProcesses.samplesByPID,
            elapsed: elapsed,
            limit: limit
        )
        return MetricSpikeSample(
            value: SystemMetricReader.cpuUsage(from: firstTicks, to: secondTicks),
            timestamp: secondTicks.timestamp,
            processes: resourceSnapshots(active, kind: .cpu, limit: limit)
        )
    }

    private static func memorySample(
        limit: Int,
        cancellationContext: ProcessCancellationContext
    ) throws -> MetricSpikeSample {
        let processes = try ProcessResourceReader.readSamples(cancellationContext: cancellationContext)
        try cancellationContext.checkCancellation()
        let value = try SystemMetricReader.readMemoryUsage()
        return MetricSpikeSample(
            value: value,
            timestamp: Date(),
            processes: resourceSnapshots(processes, kind: .memory, limit: limit)
        )
    }

    private static func networkSample(
        metric: MetricSpikeKind,
        limit: Int,
        cancellationContext: ProcessCancellationContext
    ) async throws -> MetricSpikeSample {
        let sortMode: ProcessNetworkSortMode = metric == .networkUp ? .upload : .download
        let firstProcesses = try ProcessNetworkReader.readSampleFrame(timeout: 2, cancellationContext: cancellationContext)
        let firstCounters = try SystemMetricReader.readNetworkCounters()
        try Task.checkCancellation()
        try cancellationContext.checkCancellation()
        try await Task.sleep(for: .milliseconds(350))
        try Task.checkCancellation()
        try cancellationContext.checkCancellation()
        let secondProcesses = try ProcessNetworkReader.readSampleFrame(timeout: 2, cancellationContext: cancellationContext)
        let secondCounters = try SystemMetricReader.readNetworkCounters()
        let processSample = networkSample(
            current: Array(secondProcesses.samplesByPID.values),
            previous: firstProcesses.samplesByPID,
            elapsed: secondProcesses.timestamp.timeIntervalSince(firstProcesses.timestamp),
            timestamp: secondCounters.timestamp,
            metric: metric,
            limit: limit,
            sortMode: sortMode
        )
        return MetricSpikeSample(
            value: SystemMetricReader.networkSpeed(metric: metric, from: firstCounters, to: secondCounters),
            timestamp: secondCounters.timestamp,
            processes: processSample.processes
        )
    }

    private static func confirmedSpike(
        original: MetricSpikeCandidate,
        sample: MetricSpikeSample,
        thresholds: ThresholdConfig,
        spikeDeltas: SpikeDeltaConfig
    ) -> MetricSpikeConfirmation? {
        let rule = original.metric.rule(for: thresholds, spikeDeltaConfig: spikeDeltas)
        let currentValue = sample.value
        let previousValue = original.previousValue
        let delta = currentValue - previousValue
        guard currentValue >= rule.minimumValue, delta >= rule.minimumDelta else {
            return nil
        }

        let valueScore = currentValue / max(rule.minimumValue, 1)
        let deltaScore = delta / max(rule.minimumDelta, 1)
        let candidate = MetricSpikeCandidate(
            metric: original.metric,
            previousValue: previousValue,
            currentValue: currentValue,
            delta: delta,
            timestamp: sample.timestamp,
            score: valueScore + deltaScore
        )
        return MetricSpikeConfirmation(candidate: candidate, processes: sample.processes)
    }

    static func networkSnapshots(
        current: [RawProcessNetworkSample],
        previous: [Int: RawProcessNetworkSample],
        elapsed: TimeInterval,
        metric: MetricSpikeKind,
        limit: Int,
        sortMode: ProcessNetworkSortMode
    ) -> [SpikeProcessSnapshot] {
        networkSample(
            current: current,
            previous: previous,
            elapsed: elapsed,
            timestamp: Date(),
            metric: metric,
            limit: limit,
            sortMode: sortMode
        ).processes
    }

    private static func networkSample(
        current: [RawProcessNetworkSample],
        previous: [Int: RawProcessNetworkSample],
        elapsed: TimeInterval,
        timestamp: Date,
        metric: MetricSpikeKind,
        limit: Int,
        sortMode: ProcessNetworkSortMode
    ) -> MetricSpikeSample {
        let active = ProcessNetworkReader.activeProcesses(
            current: current,
            previous: previous,
            elapsed: elapsed
        )
        let value: Int64 = active.reduce(0) { partial, process in
            switch metric {
            case .networkUp:
                return partial + process.uploadBytesPerSec
            default:
                return partial + process.downloadBytesPerSec
            }
        }
        let directional = active.filter { process in
            switch metric {
            case .networkUp:
                return process.uploadBytesPerSec > 0
            default:
                return process.downloadBytesPerSec > 0
            }
        }
        let processes = ProcessNetworkReader.sortedProcesses(
            directional,
            by: sortMode,
            limit: limit
        ).map { process in
            let valueText: String
            let bytesPerSecond: Int64
            switch metric {
            case .networkUp:
                bytesPerSecond = process.uploadBytesPerSec
                valueText = "↑\(formatSpeed(process.uploadBytesPerSec))"
            default:
                bytesPerSecond = process.downloadBytesPerSec
                valueText = "↓\(formatSpeed(process.downloadBytesPerSec))"
            }
            return SpikeProcessSnapshot(
                pid: process.pid,
                name: process.name,
                valueText: valueText,
                fraction: min(log10(Double(bytesPerSecond) + 1) / 7, 1),
                metric: .network
            )
        }
        return MetricSpikeSample(value: Double(value), timestamp: timestamp, processes: processes)
    }

    private static func formatSpeed(_ bytesPerSecond: Int64) -> String {
        MetricDisplayItem.formatSpeed(Double(bytesPerSecond)).trimmingCharacters(in: .whitespaces) + "/s"
    }
}

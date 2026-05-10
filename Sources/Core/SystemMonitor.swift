import Defaults
import Darwin
import Foundation
import IOKit
import Observation

// ═══════════════════════════════════════════════════════════════
// MARK: - System Monitor (CPU + Memory + Disk + GPU)
// ═══════════════════════════════════════════════════════════════

/// Unified system metrics collector.
/// Provides CPU%, memory usage, disk usage, network speed, and GPU utilization.
@Observable
final class SystemMonitor: @unchecked Sendable {
    private static let bytesPerGB: Double = 1024 * 1024 * 1024

    private(set) var cpuUsage: Double = 0.0
    private(set) var memoryUsage: Double = 0.0
    private(set) var memoryUsedGB: Double = 0.0
    private(set) var memoryTotalGB: Double = 0.0
    private(set) var diskUsage: Double = 0.0
    private(set) var diskUsedGB: Double = 0.0
    private(set) var diskTotalGB: Double = 0.0
    private(set) var netSpeedIn: Double = 0.0   // bytes/sec download
    private(set) var netSpeedOut: Double = 0.0  // bytes/sec upload
    private(set) var gpuUsage: Double = 0.0     // GPU device utilization %

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var metricsContinuation: AsyncStream<Void>.Continuation?
    /// Yields once per tick after all properties are updated on main thread.
    /// Re-created each time `start()` is called.
    @ObservationIgnored private(set) var metricsStream: AsyncStream<Void> = AsyncStream.makeStream().stream
    @ObservationIgnored private let queue = DispatchQueue(label: "com.traypulsy.system", qos: .utility)
    @ObservationIgnored private var interval: TimeInterval
    @ObservationIgnored private let pageSize: Double  // cached at init, never changes at runtime
    @ObservationIgnored private let totalMemory: Double  // cached at init — physicalMemory never changes

    @ObservationIgnored var enabledMetrics: Set<MetricKind> {
        get {
            metricStateLock.withLock { enabledMetricsStorage }
        }
        set {
            configureMetrics(
                enabledMetrics: newValue,
                recordedMetrics: recordedMetrics,
                recordedMetricItems: recordedMetricItems
            )
        }
    }
    @ObservationIgnored var recordedMetrics: Set<MetricKind> {
        get {
            metricStateLock.withLock { recordedMetricsStorage }
        }
        set {
            configureMetrics(
                enabledMetrics: enabledMetrics,
                recordedMetrics: newValue,
                recordedMetricItems: recordedMetricItems
            )
        }
    }
    @ObservationIgnored var recordedMetricItems: Set<MetricDisplayItem> {
        get {
            metricStateLock.withLock { recordedMetricItemsStorage }
        }
        set {
            configureMetrics(
                enabledMetrics: enabledMetrics,
                recordedMetrics: recordedMetrics,
                recordedMetricItems: newValue
            )
        }
    }

    /// 30-min ring buffer of metric history for sparkline / trend charts.
    @ObservationIgnored private(set) var history: MetricsHistory

    struct StorageInfo: Sendable {
        let usagePercent: Double, usedGB: Double, totalGB: Double
    }

    enum MetricKind: CaseIterable, Codable, Sendable {
        case cpu, memory, disk, network, gpu
    }

    // CPU state (host_cpu_load_info tick counters)
    @ObservationIgnored private var prevUser: UInt64 = 0
    @ObservationIgnored private var prevSystem: UInt64 = 0
    @ObservationIgnored private var prevIdle: UInt64 = 0
    @ObservationIgnored private var prevNice: UInt64 = 0

    // Network state (byte counters from getifaddrs)
    @ObservationIgnored private var prevNetInBytes: UInt64 = 0
    @ObservationIgnored private var prevNetOutBytes: UInt64 = 0
    @ObservationIgnored private var netInitialized: Bool = false
    @ObservationIgnored private let metricStateLock = NSLock()
    @ObservationIgnored private var enabledMetricsStorage = Set(MetricKind.allCases)
    @ObservationIgnored private var recordedMetricsStorage = Set(MetricKind.allCases)
    @ObservationIgnored private var recordedMetricItemsStorage = Set(MetricDisplayItem.allCases)
    @ObservationIgnored private var previousTickMetrics: Set<MetricKind> = []
    @ObservationIgnored private var hasPreviousTickMetrics = false
    @ObservationIgnored private var metricsDisabledSinceLastTick: Set<MetricKind> = []
    @ObservationIgnored private var metricConfigGeneration: UInt64 = 0

    // Disk throttling — capacity changes slowly, re-read every ~30s
    @ObservationIgnored private var lastDiskResult = StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
    @ObservationIgnored private var lastDiskTick: Int = 0
    @ObservationIgnored private static let diskThrottleTicks: Int = 30  // at 1s interval ≈ 30 seconds

    // Cached GPU IORegistry service (avoids per-tick lookup)
    @ObservationIgnored private var cachedGPUService: io_service_t = 0
    @ObservationIgnored private var gpuServiceCached: Bool = false

    init() {
        self.interval = Defaults[.sampleInterval].seconds
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        self.pageSize = Double(ps > 0 ? ps : 4096)
        self.totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        self.history = MetricsHistory(maxDuration: 1800, sampleInterval: interval)
    }

    func start() {
        _ = readCPUPercent()   // seed initial tick counters
        _ = readMemoryStats()
        lastDiskResult = readDiskStats()
        _ = readNetBytes()     // seed initial counters
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        metricsStream = stream
        metricsContinuation = continuation
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + interval, repeating: interval)
        timer?.setEventHandler { [weak self] in self?.tick() }
        timer?.resume()
    }

    func stop() {
        timer?.cancel(); timer = nil
        metricsContinuation?.finish()
        metricsContinuation = nil
        metricStateLock.lock()
        previousTickMetrics.removeAll()
        hasPreviousTickMetrics = false
        metricsDisabledSinceLastTick.removeAll()
        metricConfigGeneration &+= 1
        metricStateLock.unlock()
        releaseGPUService()
    }

    /// Restart the timer with a new sample interval (for runtime config changes).
    func reconfigure(sampleInterval: TimeInterval, maxDuration: TimeInterval = 1800) {
        let wasRunning = timer != nil
        stop()
        interval = sampleInterval
        history.reconfigure(maxDuration: maxDuration, sampleInterval: sampleInterval)
        if wasRunning { start() }
    }

    func configureMetrics(
        enabledMetrics newEnabledMetrics: Set<MetricKind>,
        recordedMetrics newRecordedMetrics: Set<MetricKind>,
        recordedMetricItems newRecordedMetricItems: Set<MetricDisplayItem>
    ) {
        let liveMetricsToClear = metricStateLock.withLock {
            let oldEnabledMetrics = enabledMetricsStorage
            let oldRecordedMetrics = recordedMetricsStorage
            let oldRecordedMetricItems = recordedMetricItemsStorage
            guard Self.metricConfigurationChanged(
                oldEnabledMetrics: oldEnabledMetrics,
                newEnabledMetrics: newEnabledMetrics,
                oldRecordedMetrics: oldRecordedMetrics,
                newRecordedMetrics: newRecordedMetrics,
                oldRecordedMetricItems: oldRecordedMetricItems,
                newRecordedMetricItems: newRecordedMetricItems
            ) else {
                return Set<MetricKind>()
            }

            enabledMetricsStorage = newEnabledMetrics
            recordedMetricsStorage = newRecordedMetrics
            recordedMetricItemsStorage = newRecordedMetricItems
            metricsDisabledSinceLastTick.formUnion(oldEnabledMetrics.subtracting(newEnabledMetrics))
            metricConfigGeneration &+= 1
            return Self.liveMetricsToClearAfterEnabledMetricsChange(
                oldEnabledMetrics: oldEnabledMetrics,
                newEnabledMetrics: newEnabledMetrics,
                metricsDisabledSinceLastTick: metricsDisabledSinceLastTick
            )
        }
        if liveMetricsToClear.contains(.cpu) {
            cpuUsage = 0
        }
        if liveMetricsToClear.contains(.network) {
            netSpeedIn = 0
            netSpeedOut = 0
        }
    }

    // MARK: - Tick (only read enabled metrics)

    private func tick() {
        // Snapshot which metrics to read (set only mutates on main thread)
        let tickState = metricStateLock.withLock {
            let metrics = enabledMetricsStorage
            let resetMetrics = Self.metricsNeedingBaselineReset(
                enabledMetrics: metrics,
                previousTickMetrics: previousTickMetrics,
                hasPreviousTickMetrics: hasPreviousTickMetrics,
                metricsDisabledSinceLastTick: metricsDisabledSinceLastTick
            )
            let recordingScope = Self.historyRecordingScope(
                enabledMetrics: metrics,
                recordedMetrics: recordedMetricsStorage,
                recordedMetricItems: recordedMetricItemsStorage,
                resetMetrics: resetMetrics
            )
            previousTickMetrics = metrics
            hasPreviousTickMetrics = true
            metricsDisabledSinceLastTick.subtract(metrics)
            return TickState(
                metrics: metrics,
                resetMetrics: resetMetrics,
                recordingScope: recordingScope,
                generation: metricConfigGeneration
            )
        }
        let metrics = tickState.metrics
        let cpuNeedsBaselineReset = tickState.resetMetrics.contains(.cpu)
        let networkNeedsBaselineReset = tickState.resetMetrics.contains(.network)
        let recordingScope = tickState.recordingScope
        let configGeneration = tickState.generation
        var cpu: Double = 0
        var mem = StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
        var disk = StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
        var netIn: Double = 0, netOut: Double = 0
        var gpu: Double = 0

        if metrics.contains(.cpu) {
            if cpuNeedsBaselineReset {
                _ = readCPUPercent()
            } else {
                cpu = readCPUPercent()
            }
        }
        if metrics.contains(.memory) { mem = readMemoryStats() }
        if metrics.contains(.disk) {
            lastDiskTick += 1
            if lastDiskTick >= Self.diskThrottleTicks {
                lastDiskResult = readDiskStats()
                lastDiskTick = 0
            }
            disk = lastDiskResult
        }
        if metrics.contains(.network) { (netIn, netOut) = readNetSpeed(resetBaseline: networkNeedsBaselineReset) }
        if metrics.contains(.gpu)    { gpu = readGPUUtilization() }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let shouldPublish = self.metricStateLock.withLock {
                Self.shouldPublishTick(
                sampleGeneration: configGeneration,
                currentGeneration: self.metricConfigGeneration
                )
            }
            guard shouldPublish else { return }
            if metrics.contains(.cpu) {
                self.cpuUsage = Self.publishedCPUUsage(sampledValue: cpu, needsBaselineReset: cpuNeedsBaselineReset)
            }
            if metrics.contains(.memory) {
                self.memoryUsage = mem.usagePercent
                self.memoryUsedGB = mem.usedGB
                self.memoryTotalGB = mem.totalGB
            }
            if metrics.contains(.disk) {
                self.diskUsage = disk.usagePercent
                self.diskUsedGB = disk.usedGB
                self.diskTotalGB = disk.totalGB
            }
            if metrics.contains(.network) {
                self.netSpeedIn = netIn
                self.netSpeedOut = netOut
            }
            if metrics.contains(.gpu) { self.gpuUsage = gpu }
            self.recordHistory(metrics: recordingScope.metrics, metricItems: recordingScope.metricItems)
            self.metricsContinuation?.yield()
        }
    }

    private struct TickState {
        let metrics: Set<MetricKind>
        let resetMetrics: Set<MetricKind>
        let recordingScope: (metrics: Set<MetricKind>, metricItems: Set<MetricDisplayItem>)
        let generation: UInt64
    }

    static func historyRecordingScope(
        enabledMetrics: Set<MetricKind>,
        recordedMetrics: Set<MetricKind>,
        recordedMetricItems: Set<MetricDisplayItem>,
        resetMetrics: Set<MetricKind>
    ) -> (metrics: Set<MetricKind>, metricItems: Set<MetricDisplayItem>) {
        var metrics = recordedMetrics
        var items = recordedMetricItems
        if enabledMetrics.contains(.cpu), resetMetrics.contains(.cpu) {
            metrics.remove(.cpu)
            items.remove(.cpu)
        }
        if enabledMetrics.contains(.network), resetMetrics.contains(.network) {
            metrics.remove(.network)
            items.remove(.networkDown)
            items.remove(.networkUp)
        }
        return (metrics, items)
    }

    static func metricsNeedingBaselineReset(
        enabledMetrics: Set<MetricKind>,
        previousTickMetrics: Set<MetricKind>,
        hasPreviousTickMetrics: Bool,
        metricsDisabledSinceLastTick: Set<MetricKind>
    ) -> Set<MetricKind> {
        var metrics: Set<MetricKind> = []
        if enabledMetrics.contains(.cpu),
           metricsDisabledSinceLastTick.contains(.cpu)
            || (hasPreviousTickMetrics && !previousTickMetrics.contains(.cpu)) {
            metrics.insert(.cpu)
        }
        if enabledMetrics.contains(.network),
           metricsDisabledSinceLastTick.contains(.network) || !previousTickMetrics.contains(.network) {
            metrics.insert(.network)
        }
        return metrics
    }

    static func liveMetricsToClearAfterEnabledMetricsChange(
        oldEnabledMetrics: Set<MetricKind>,
        newEnabledMetrics: Set<MetricKind>,
        metricsDisabledSinceLastTick: Set<MetricKind>
    ) -> Set<MetricKind> {
        let disabledMetrics = oldEnabledMetrics.subtracting(newEnabledMetrics)
        var metrics: Set<MetricKind> = []
        if disabledMetrics.contains(.cpu)
            || (newEnabledMetrics.contains(.cpu) && metricsDisabledSinceLastTick.contains(.cpu)) {
            metrics.insert(.cpu)
        }
        if disabledMetrics.contains(.network)
            || (newEnabledMetrics.contains(.network) && metricsDisabledSinceLastTick.contains(.network)) {
            metrics.insert(.network)
        }
        return metrics
    }

    static func metricConfigurationChanged(
        oldEnabledMetrics: Set<MetricKind>,
        newEnabledMetrics: Set<MetricKind>,
        oldRecordedMetrics: Set<MetricKind>,
        newRecordedMetrics: Set<MetricKind>,
        oldRecordedMetricItems: Set<MetricDisplayItem>,
        newRecordedMetricItems: Set<MetricDisplayItem>
    ) -> Bool {
        oldEnabledMetrics != newEnabledMetrics
            || oldRecordedMetrics != newRecordedMetrics
            || oldRecordedMetricItems != newRecordedMetricItems
    }

    static func shouldPublishTick(sampleGeneration: UInt64, currentGeneration: UInt64) -> Bool {
        sampleGeneration == currentGeneration
    }

    static func publishedCPUUsage(sampledValue: Double, needsBaselineReset: Bool) -> Double {
        needsBaselineReset ? 0 : sampledValue
    }

    /// Record current metrics into history buffer. Carry forward last known values for disabled metrics.
    private func recordHistory(metrics: Set<MetricKind>, metricItems: Set<MetricDisplayItem>) {
        let last = history.lastSnapshot
        history.record(MetricSnapshot(
            cpuUsage:     metrics.contains(.cpu)     ? cpuUsage     : (last?.cpuUsage     ?? 0),
            gpuUsage:     metrics.contains(.gpu)     ? gpuUsage     : (last?.gpuUsage     ?? 0),
            memoryUsage:  metrics.contains(.memory)  ? memoryUsage  : (last?.memoryUsage  ?? 0),
            diskUsage:    metrics.contains(.disk)    ? diskUsage    : (last?.diskUsage    ?? 0),
            netSpeedIn:   metricItems.contains(.networkDown) ? netSpeedIn   : (last?.netSpeedIn   ?? 0),
            netSpeedOut:  metricItems.contains(.networkUp)   ? netSpeedOut  : (last?.netSpeedOut  ?? 0),
            timestamp:    Date(),
            recordedMetrics: metrics,
            recordedMetricItems: metricItems
        ))
    }

    /// Returns the current value for a given speed source
    func valueForSource(_ source: SpeedSource) -> Double {
        switch source {
        case .cpu:  return cpuUsage
        case .gpu:   return gpuUsage
        case .memory: return memoryUsage
        case .disk:  return diskUsage
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - CPU (host_statistics — zero-allocation aggregate)
    // ═════════════════════════════════════════════════════════

    private func readCPUPercent() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user   = UInt64(load.cpu_ticks.0)  // CPU_STATE_USER
        let system = UInt64(load.cpu_ticks.1)  // CPU_STATE_SYSTEM
        let idle   = UInt64(load.cpu_ticks.2)  // CPU_STATE_IDLE
        let nice   = UInt64(load.cpu_ticks.3)  // CPU_STATE_NICE

        let dU = user - prevUser, dS = system - prevSystem
        let dI = idle - prevIdle, dN = nice - prevNice
        prevUser = user; prevSystem = system
        prevIdle = idle; prevNice = nice
        let total = dU + dS + dI + dN
        guard total > 0 else { return 0 }
        return min(100.0, Double(dU + dS + dN) / Double(total) * 100.0)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Memory (host_statistics64)
    // ═════════════════════════════════════════════════════════

    private func readMemoryStats() -> StorageInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0) }

        let total = totalMemory
        let free = Double(stats.free_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let used = total - free - purgeable - external
        let usage = total > 0 ? min(100, max(0, used / total * 100)) : 0
        return StorageInfo(usagePercent: min(100, usage), usedGB: used / Self.bytesPerGB, totalGB: total / Self.bytesPerGB)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Disk (FileManager)
    // ═════════════════════════════════════════════════════════

    private func readDiskStats() -> StorageInfo {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            guard let total = values.volumeTotalCapacity,
                  let avail = values.volumeAvailableCapacityForImportantUsage else {
                return StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
            }
            let totalD = Double(total)
            let usedD = totalD - Double(avail)
            let pct = totalD > 0 ? usedD / totalD * 100 : 0
            return StorageInfo(usagePercent: min(100, pct), usedGB: usedD / Self.bytesPerGB, totalGB: totalD / Self.bytesPerGB)
        } catch {
            return StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Network (getifaddrs)
    // ═════════════════════════════════════════════════════════

    private func readNetBytes() -> (inBytes: UInt64, outBytes: UInt64) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }

        var iface: UnsafeMutablePointer<ifaddrs>? = first
        while let current = iface {
            guard let namePtr = current.pointee.ifa_name else {
                iface = current.pointee.ifa_next
                continue
            }
            // Compare raw C bytes — avoid Swift String allocation per interface
            let b0 = namePtr.pointee, b1 = (namePtr + 1).pointee
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
        return (totalIn, totalOut)
    }

    func readNetSpeed(resetBaseline: Bool = false) -> (inBytesPerSec: Double, outBytesPerSec: Double) {
        let (curIn, curOut) = readNetBytes()

        guard netInitialized, !resetBaseline else {
            prevNetInBytes = curIn
            prevNetOutBytes = curOut
            netInitialized = true
            return (0, 0)
        }

        let deltaIn = curIn >= prevNetInBytes ? curIn - prevNetInBytes : 0
        let deltaOut = curOut >= prevNetOutBytes ? curOut - prevNetOutBytes : 0

        prevNetInBytes = curIn
        prevNetOutBytes = curOut

        let sec = max(interval, 0.01)
        return (Double(deltaIn) / sec, Double(deltaOut) / sec)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - GPU (IORegistry AGXAccelerator — cached service)
    // ═════════════════════════════════════════════════════════

    /// Lazily look up and cache the GPU IORegistry service.
    private func getGPUService() -> io_service_t {
        if gpuServiceCached { return cachedGPUService }
        let matching = IOServiceMatching("AGXAccelerator")
        guard let matching else {
            gpuServiceCached = true
            cachedGPUService = 0
            return 0
        }
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            gpuServiceCached = true
            cachedGPUService = 0
            return 0
        }
        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        cachedGPUService = service
        gpuServiceCached = true
        return service
    }

    private func releaseGPUService() {
        if gpuServiceCached && cachedGPUService != 0 {
            IOObjectRelease(cachedGPUService)
        }
        cachedGPUService = 0
        gpuServiceCached = false
    }

    private func readGPUUtilization() -> Double {
        let service = getGPUService()
        guard service != 0 else { return 0 }

        // Read only the "PerformanceStatistics" key instead of the full property dictionary
        let key = "PerformanceStatistics" as CFString
        guard let perfObj = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0),
              let perfStats = perfObj.takeRetainedValue() as? [String: Any],
              let util = perfStats["Device Utilization %"] as? Int else {
            return 0
        }

        return min(100.0, max(0.0, Double(util)))
    }
}

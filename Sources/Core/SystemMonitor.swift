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
    static let shared = SystemMonitor()
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

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.runcatx.system", qos: .utility)
    private var interval: TimeInterval
    private let pageSize: Double  // cached at init, never changes at runtime

    var enabledMetrics: Set<MetricKind> = Set(MetricKind.allCases)

    struct StorageInfo: Sendable {
        let usagePercent: Double, usedGB: Double, totalGB: Double
    }

    enum MetricKind: CaseIterable {
        case cpu, memory, disk, network, gpu
    }

    // CPU state (host_cpu_load_info tick counters)
    private var prevUser: UInt64 = 0
    private var prevSystem: UInt64 = 0
    private var prevIdle: UInt64 = 0
    private var prevNice: UInt64 = 0

    // Network state (byte counters from getifaddrs)
    private var prevNetInBytes: UInt64 = 0
    private var prevNetOutBytes: UInt64 = 0
    private var netInitialized: Bool = false

    // Cached GPU IORegistry service (avoids per-tick lookup)
    private var cachedGPUService: io_service_t = 0
    private var gpuServiceCached: Bool = false

    private init() {
        self.interval = Defaults[.sampleInterval].seconds
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        self.pageSize = Double(ps > 0 ? ps : 4096)
    }

    func start() {
        _ = readCPUPercent()   // seed initial tick counters
        _ = readMemoryStats()
        _ = readDiskStats()
        _ = readNetBytes()     // seed initial counters
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + interval, repeating: interval)
        timer?.setEventHandler { [weak self] in self?.tick() }
        timer?.resume()
    }

    func stop() {
        timer?.cancel(); timer = nil
        releaseGPUService()
    }

    /// Restart the timer with a new sample interval (for runtime config changes).
    func reconfigure(sampleInterval: TimeInterval) {
        let wasRunning = timer != nil
        stop()
        interval = sampleInterval
        if wasRunning { start() }
    }

    // MARK: - Tick (only read enabled metrics)

    private func tick() {
        // Snapshot which metrics to read (set only mutates on main thread)
        let metrics = enabledMetrics
        var cpu: Double = 0
        var mem = StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
        var disk = StorageInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
        var netIn: Double = 0, netOut: Double = 0
        var gpu: Double = 0

        if metrics.contains(.cpu)    { cpu = readCPUPercent() }
        if metrics.contains(.memory) { mem = readMemoryStats() }
        if metrics.contains(.disk)   { disk = readDiskStats() }
        if metrics.contains(.network) { (netIn, netOut) = readNetSpeed() }
        if metrics.contains(.gpu)    { gpu = readGPUUtilization() }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if metrics.contains(.cpu)    { self.cpuUsage = cpu }
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
        }
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

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let usedPages = UInt64(stats.active_count) +
                        UInt64(stats.wire_count) +
                        UInt64(stats.compressor_page_count)
        let used = Double(usedPages) * pageSize
        let usage = total > 0 ? used / total * 100 : 0
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
            let name = String(cString: namePtr)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else {
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

    func readNetSpeed() -> (inBytesPerSec: Double, outBytesPerSec: Double) {
        let (curIn, curOut) = readNetBytes()

        guard netInitialized else {
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

        var props: Unmanaged<CFMutableDictionary>?
        let pr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard pr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
            return 0
        }

        guard let perfStats = dict["PerformanceStatistics"] as? [String: Any],
              let util = perfStats["Device Utilization %"] as? Int else {
            return 0
        }

        return min(100.0, max(0.0, Double(util)))
    }
}

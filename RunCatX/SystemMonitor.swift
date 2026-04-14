import Foundation
import Darwin

// ═══════════════════════════════════════════════════════════════
// MARK: - System Monitor (CPU + Memory + Disk)
// ═══════════════════════════════════════════════════════════════

/// Unified system metrics collector.
/// Provides CPU%, memory usage, and disk usage via kernel APIs.
final class SystemMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var cpuUsage: Double = 0.0
    @Published private(set) var memoryUsage: Double = 0.0
    @Published private(set) var memoryUsedGB: Double = 0.0
    @Published private(set) var memoryTotalGB: Double = 0.0
    @Published private(set) var diskUsage: Double = 0.0
    @Published private(set) var diskUsedGB: Double = 0.0
    @Published private(set) var diskTotalGB: Double = 0.0

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.runcatx.system", qos: .utility)
    private let interval: TimeInterval

    // CPU state
    private var prevUser: UInt64 = 0
    private var prevSystem: UInt64 = 0
    private var prevIdle: UInt64 = 0
    private var prevNice: UInt64 = 0

    init(sampleInterval: TimeInterval = 1.0) { self.interval = sampleInterval }

    func start() {
        _ = readCPUStats()
        _ = readMemoryStats()
        _ = readDiskStats()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + interval, repeating: interval)
        timer?.setEventHandler { [weak self] in self?.tick() }
        timer?.resume()
    }

    func stop() { timer?.cancel(); timer = nil }

    // MARK: - Tick

    private func tick() {
        let cpu = readCPUPercent()
        let mem = readMemoryStats()
        let disk = readDiskStats()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cpuUsage = cpu
            self.memoryUsage = mem.usagePercent
            self.memoryUsedGB = mem.usedGB
            self.memoryTotalGB = mem.totalGB
            self.diskUsage = disk.usagePercent
            self.diskUsedGB = disk.usedGB
            self.diskTotalGB = disk.totalGB
        }
    }

    /// Returns the current value for a given speed source
    func valueForSource(_ source: SpeedSource) -> Double {
        switch source {
        case .cpu: return cpuUsage
        case .memory: return memoryUsage
        case .disk: return diskUsage
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - CPU (host_processor_info)
    // ═════════════════════════════════════════════════════════

    private func readCPUPercent() -> Double {
        let s = readCPUStats()
        let dU = s.user - prevUser, dS = s.system - prevSystem
        let dI = s.idle - prevIdle, dN = s.nice - prevNice
        prevUser = s.user; prevSystem = s.system
        prevIdle = s.idle; prevNice = s.nice
        let total = dU + dS + dI + dN
        guard total > 0 else { return 0 }
        return min(100.0, Double(dU + dS + dN) / Double(total) * 100.0)
    }

    private func readCPUStats() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        var infoPtr: processor_info_array_t?
        var numCPUs: natural_t = 0
        var infoSize: mach_msg_type_number_t = 0
        let kerr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                       &numCPUs, &infoPtr, &infoSize)
        guard kerr == KERN_SUCCESS, let raw = infoPtr else { return (0, 0, 0, 0) }
        let count = Int(numCPUs)
        var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        for i in 0..<count {
            let b = i * 4
            user += UInt64(raw[b + Int(CPU_STATE_USER)])
            sys   += UInt64(raw[b + Int(CPU_STATE_SYSTEM)])
            idle  += UInt64(raw[b + Int(CPU_STATE_IDLE)])
            nice  += UInt64(raw[b + Int(CPU_STATE_NICE)])
        }
        let size = vm_size_t(infoSize) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: raw), size)
        return (user, sys, idle, nice)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Memory (host_statistics64)
    // ═════════════════════════════════════════════════════════

    private struct MemInfo {
        let usagePercent: Double, usedGB: Double, totalGB: Double
    }

    private func readMemoryStats() -> MemInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemInfo(usagePercent: 0, usedGB: 0, totalGB: 0) }

        // Read page size via host_page_size() (safer C API)
        var pageSizeValue: vm_size_t = 0
        let pageSizeResult = host_page_size(mach_host_self(), &pageSizeValue)
        let pageSize = Double(pageSizeResult == KERN_SUCCESS ? pageSizeValue : 4096)
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let usage = total > 0 ? used / total * 100 : 0
        let gb: Double = 1024 * 1024 * 1024
        return MemInfo(usagePercent: min(100, usage), usedGB: used / gb, totalGB: total / gb)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: - Disk (FileManager)
    // ═════════════════════════════════════════════════════════

    private struct DiskInfo {
        let usagePercent: Double, usedGB: Double, totalGB: Double
    }

    private func readDiskStats() -> DiskInfo {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            guard let total = values.volumeTotalCapacity,
                  let avail = values.volumeAvailableCapacityForImportantUsage else {
                return DiskInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
            }
            let totalD = Double(total)
            let availD = Double(avail)
            let usedD = totalD - availD
            let gb: Double = 1024.0 * 1024.0 * 1024.0
            let pct = totalD > 0 ? usedD / totalD * 100 : 0
            return DiskInfo(usagePercent: min(100, pct), usedGB: usedD / gb, totalGB: totalD / gb)
        } catch {
            return DiskInfo(usagePercent: 0, usedGB: 0, totalGB: 0)
        }
    }
}

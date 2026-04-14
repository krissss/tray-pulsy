import Foundation

/// Samples CPU usage via host_processor_info().
final class CPUMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var cpuUsage: Double = 0.0

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.runcatx.cpu", qos: .utility)
    private let interval: TimeInterval

    private var prevUser: UInt64 = 0
    private var prevSystem: UInt64 = 0
    private var prevIdle: UInt64 = 0
    private var prevNice: UInt64 = 0

    init(sampleInterval: TimeInterval = 0.5) { self.interval = sampleInterval }

    func start() {
        _ = readCPUStats()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + interval, repeating: interval)
        timer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.tick()
        }
        timer?.resume()
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        let s = readCPUStats()
        let dU = s.user - prevUser, dS = s.system - prevSystem
        let dI = s.idle - prevIdle, dN = s.nice - prevNice
        prevUser = s.user; prevSystem = s.system
        prevIdle = s.idle; prevNice = s.nice
        let total = dU + dS + dI + dN
        guard total > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.cpuUsage = min(100.0, Double(dU + dS + dN) / Double(total) * 100.0)
        }
    }

    // MARK: - Raw kernel call

    private func readCPUStats() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        var infoPtr: processor_info_array_t?
        var numCPUs: natural_t = 0
        var infoSize: mach_msg_type_number_t = 0

        let kerr = host_processor_info(mach_host_self(),
                                       PROCESSOR_CPU_LOAD_INFO,
                                       &numCPUs,
                                       &infoPtr,
                                       &infoSize)

        guard kerr == KERN_SUCCESS, let raw = infoPtr else {
            return (0, 0, 0, 0)
        }

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
}

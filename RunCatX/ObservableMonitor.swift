import Foundation
import Combine

/// Thin ObservableObject wrapper around SystemMonitor for SwiftUI bindings.
/// The real monitor is owned by StatusBarController; this just mirrors values.
final class ObservableMonitor: ObservableObject, @unchecked Sendable {
    nonisolated(unsafe) static let shared = ObservableMonitor()

    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var diskUsage: Double = 0
    @Published private(set) var gpuUsage: Double = 0
    @Published private(set) var netSpeedIn: Double = 0
    @Published private(set) var netSpeedOut: Double = 0
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var memoryTotalGB: Double = 0

    /// Called by StatusBarController on each tick to keep this in sync.
    func sync(from monitor: SystemMonitor) {
        cpuUsage = monitor.cpuUsage
        memoryUsage = monitor.memoryUsage
        diskUsage = monitor.diskUsage
        gpuUsage = monitor.gpuUsage
        netSpeedIn = monitor.netSpeedIn
        netSpeedOut = monitor.netSpeedOut
        memoryUsedGB = monitor.memoryUsedGB
        memoryTotalGB = monitor.memoryTotalGB
    }

    /// Convenience for settings view — returns value for current source.
    func valueForSource(_ source: SpeedSource) -> Double {
        switch source {
        case .cpu:     return cpuUsage
        case .gpu:      return gpuUsage
        case .memory:   return memoryUsage
        case .disk:     return diskUsage
        }
    }
}

import Foundation
import Observation

/// Thin observable wrapper around SystemMonitor for SwiftUI bindings.
/// The real monitor is owned by StatusBarController; this just mirrors values.
@MainActor @Observable
final class ObservableMonitor: @unchecked Sendable {
    static let shared = ObservableMonitor()

    private(set) var cpuUsage: Double = 0
    private(set) var memoryUsage: Double = 0
    private(set) var diskUsage: Double = 0
    private(set) var gpuUsage: Double = 0
    private(set) var netSpeedIn: Double = 0
    private(set) var netSpeedOut: Double = 0
    private(set) var memoryUsedGB: Double = 0
    private(set) var memoryTotalGB: Double = 0

    /// Called by StatusBarController on each tick to keep this in sync.
    func sync(from monitor: SystemMonitor) {
        setIfChanged(\.cpuUsage, monitor.cpuUsage)
        setIfChanged(\.memoryUsage, monitor.memoryUsage)
        setIfChanged(\.diskUsage, monitor.diskUsage)
        setIfChanged(\.gpuUsage, monitor.gpuUsage)
        setIfChanged(\.netSpeedIn, monitor.netSpeedIn)
        setIfChanged(\.netSpeedOut, monitor.netSpeedOut)
        setIfChanged(\.memoryUsedGB, monitor.memoryUsedGB)
        setIfChanged(\.memoryTotalGB, monitor.memoryTotalGB)
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

    /// Only update the property if the value changed (avoids spurious SwiftUI redraws).
    private func setIfChanged(_ keyPath: ReferenceWritableKeyPath<ObservableMonitor, Double>, _ newValue: Double) {
        let oldValue = self[keyPath: keyPath]
        if abs(oldValue - newValue) > 0.01 {
            self[keyPath: keyPath] = newValue
        }
    }
}

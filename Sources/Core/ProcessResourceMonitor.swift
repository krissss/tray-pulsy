import Foundation
import Observation

// ═══════════════════════════════════════════════════════════════
// MARK: - Process Resource Monitor (CPU + Memory)
// ═══════════════════════════════════════════════════════════════

enum ProcessResourceKind: Sendable {
    case cpu
    case memory
}

struct ProcessResourceUsage: Identifiable, Equatable, Sendable {
    let pid: Int
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64
    let memoryPercent: Double

    var id: Int { pid }

    init(
        pid: Int,
        name: String,
        cpuPercent: Double,
        memoryBytes: Int64,
        memoryPercent: Double = 0
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = min(100, max(0, cpuPercent))
        self.memoryBytes = max(0, memoryBytes)
        self.memoryPercent = min(100, max(0, memoryPercent))
    }
}

enum ProcessResourceReader {
    static func readSamples() throws -> [ProcessResourceUsage] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        guard task.terminationStatus == 0 else {
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            throw ProcessResourceReaderError.psFailed(errorText)
        }

        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            return []
        }
        return parsePSOutput(output)
    }

    static func parsePSOutput(
        _ output: String,
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> [ProcessResourceUsage] {
        var samples: [ProcessResourceUsage] = []
        let cpuCapacity = Double(max(1, processorCount))
        let memoryTotal = Double(totalMemoryBytes)

        output.enumerateLines { line, _ in
            let columns = line.split(maxSplits: 3, omittingEmptySubsequences: true) { $0.isWhitespace }
            guard columns.count >= 4 else { return }
            guard let pid = Int(columns[0]),
                  let rawCPUPercent = Double(columns[1]),
                  let rssKB = Int64(columns[2]) else {
                return
            }

            let command = String(columns[3])
            let memoryBytes = max(0, rssKB) * 1024
            let memoryPercent = memoryTotal > 0
                ? Double(memoryBytes) / memoryTotal * 100
                : 0
            samples.append(ProcessResourceUsage(
                pid: pid,
                name: processName(from: command, fallbackPID: pid),
                cpuPercent: rawCPUPercent / cpuCapacity,
                memoryBytes: memoryBytes,
                memoryPercent: memoryPercent
            ))
        }

        return samples
    }

    static func topProcesses(
        _ samples: [ProcessResourceUsage],
        kind: ProcessResourceKind,
        limit: Int
    ) -> [ProcessResourceUsage] {
        let active = samples.filter { sample in
            switch kind {
            case .cpu:
                return sample.cpuPercent > 0
            case .memory:
                return sample.memoryBytes > 0
            }
        }

        return Array(active.sorted { lhs, rhs in
            switch kind {
            case .cpu:
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
            case .memory:
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }.prefix(limit))
    }

    private static func processName(from command: String, fallbackPID pid: Int) -> String {
        let lastComponent = URL(fileURLWithPath: command).lastPathComponent
        let trimmed = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(pid)" : trimmed
    }
}

enum ProcessResourceReaderError: LocalizedError {
    case psFailed(String)

    var errorDescription: String? {
        switch self {
        case .psFailed(let message):
            return message.isEmpty ? "ps failed" : message
        }
    }
}

@MainActor
@Observable
final class ProcessResourceMonitor {
    private(set) var processes: [ProcessResourceUsage] = []
    private(set) var isSampling: Bool = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let kind: ProcessResourceKind
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var limit: Int = 8

    init(kind: ProcessResourceKind) {
        self.kind = kind
    }

    deinit {
        sampleTask?.cancel()
    }

    func start(limit: Int = 8, sampleInterval: TimeInterval = 2) {
        self.limit = limit
        guard sampleTask == nil else { return }

        isSampling = true
        errorMessage = nil
        processes = []

        sampleTask = Task { [weak self] in
            await self?.sampleOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(sampleInterval))
                await self?.sampleOnce()
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        isSampling = false
        errorMessage = nil
        processes = []
    }

    private func sampleOnce() async {
        let result = await Task.detached(priority: .utility) {
            do {
                return Result<[ProcessResourceUsage], Error>.success(try ProcessResourceReader.readSamples())
            } catch {
                return Result<[ProcessResourceUsage], Error>.failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let samples):
            errorMessage = nil
            processes = ProcessResourceReader.topProcesses(samples, kind: kind, limit: limit)
        case .failure(let error):
            errorMessage = error.localizedDescription
            processes = []
        }
    }
}

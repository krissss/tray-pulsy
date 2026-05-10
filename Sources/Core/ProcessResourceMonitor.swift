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
    let cpuTime: TimeInterval?

    var id: Int { pid }

    init(
        pid: Int,
        name: String,
        cpuPercent: Double,
        memoryBytes: Int64,
        memoryPercent: Double = 0,
        cpuTime: TimeInterval? = nil
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = min(100, max(0, cpuPercent))
        self.memoryBytes = max(0, memoryBytes)
        self.memoryPercent = min(100, max(0, memoryPercent))
        self.cpuTime = cpuTime
    }
}

struct ProcessResourceSampleFrame: Equatable, Sendable {
    let samples: [ProcessResourceUsage]
    let samplesByPID: [Int: ProcessResourceUsage]
    let timestamp: Date

    init(samples: [ProcessResourceUsage], timestamp: Date = Date()) {
        self.samples = samples
        self.samplesByPID = Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
        self.timestamp = timestamp
    }
}

enum ProcessResourceReader {
    static func readSamples(cancellationContext: ProcessCancellationContext? = nil) throws -> [ProcessResourceUsage] {
        try cancellationContext?.checkCancellation()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,time=,rss=,comm="]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        try cancellationContext?.register(task)
        defer { cancellationContext?.unregister(task) }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        try cancellationContext?.checkCancellation()

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

    static func readSampleFrame(cancellationContext: ProcessCancellationContext? = nil) throws -> ProcessResourceSampleFrame {
        let samples = try readSamples(cancellationContext: cancellationContext)
        return ProcessResourceSampleFrame(samples: samples)
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
            let columns = line.split(maxSplits: 4, omittingEmptySubsequences: true) { $0.isWhitespace }
            guard columns.count >= 4 else { return }

            let hasCPUTime = columns.count >= 5
            let cpuTime = hasCPUTime ? parseCPUTime(String(columns[2])) : nil
            let rssColumn = hasCPUTime ? columns[3] : columns[2]
            let commandColumn = hasCPUTime ? columns[4] : columns[3]

            guard let pid = Int(columns[0]),
                  let rawCPUPercent = Double(columns[1]),
                  let rssKB = Int64(rssColumn) else {
                return
            }

            let command = String(commandColumn)
            let memoryBytes = max(0, rssKB) * 1024
            let memoryPercent = memoryTotal > 0
                ? Double(memoryBytes) / memoryTotal * 100
                : 0
            samples.append(ProcessResourceUsage(
                pid: pid,
                name: processName(from: command, fallbackPID: pid),
                cpuPercent: rawCPUPercent / cpuCapacity,
                memoryBytes: memoryBytes,
                memoryPercent: memoryPercent,
                cpuTime: cpuTime
            ))
        }

        return samples
    }

    static func activeCPUProcesses(
        current: [ProcessResourceUsage],
        previous: [Int: ProcessResourceUsage],
        elapsed: TimeInterval,
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        limit: Int
    ) -> [ProcessResourceUsage] {
        guard elapsed > 0 else { return [] }
        let cpuCapacity = Double(max(1, processorCount))
        let active = current.compactMap { sample -> ProcessResourceUsage? in
            guard let currentTime = sample.cpuTime,
                  let previousTime = previous[sample.pid]?.cpuTime else {
                return nil
            }
            let percent = max(0, currentTime - previousTime) / elapsed / cpuCapacity * 100
            guard percent > 0 else { return nil }
            return ProcessResourceUsage(
                pid: sample.pid,
                name: sample.name,
                cpuPercent: percent,
                memoryBytes: sample.memoryBytes,
                memoryPercent: sample.memoryPercent,
                cpuTime: sample.cpuTime
            )
        }

        return Array(active.sorted {
            if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
            if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(limit))
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

    private static func parseCPUTime(_ raw: String) -> TimeInterval? {
        let dayParts = raw.split(separator: "-", maxSplits: 1)
        let days: Double
        let timePart: Substring
        if dayParts.count == 2 {
            days = Double(dayParts[0]) ?? 0
            timePart = dayParts[1]
        } else {
            days = 0
            timePart = dayParts[0]
        }

        let parts = timePart.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2:
            return days * 86_400 + parts[0] * 60 + parts[1]
        case 3:
            return days * 86_400 + parts[0] * 3_600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
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
    @ObservationIgnored private var previousSamples: [Int: ProcessResourceUsage] = [:]
    @ObservationIgnored private var previousSampleDate: Date?
    @ObservationIgnored private var cancellationContext: ProcessCancellationContext?

    init(kind: ProcessResourceKind) {
        self.kind = kind
    }

    deinit {
        sampleTask?.cancel()
        cancellationContext?.cancel()
    }

    func start(limit: Int = 8, sampleInterval: TimeInterval = 2) {
        self.limit = limit
        guard sampleTask == nil else { return }

        isSampling = true
        errorMessage = nil
        processes = []
        previousSamples = [:]
        previousSampleDate = nil

        let context = ProcessCancellationContext()
        cancellationContext = context
        sampleTask = Task { [weak self] in
            await self?.sampleOnce(cancellationContext: context)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(sampleInterval))
                guard !Task.isCancelled else { break }
                await self?.sampleOnce(cancellationContext: context)
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        cancellationContext?.cancel()
        cancellationContext = nil
        isSampling = false
        errorMessage = nil
        processes = []
        previousSamples = [:]
        previousSampleDate = nil
    }

    private func sampleOnce(cancellationContext: ProcessCancellationContext) async {
        let result = await Task.detached(priority: .utility) {
            do {
                return Result<[ProcessResourceUsage], Error>.success(
                    try ProcessResourceReader.readSamples(cancellationContext: cancellationContext)
                )
            } catch {
                return Result<[ProcessResourceUsage], Error>.failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let samples):
            errorMessage = nil
            let now = Date()
            switch kind {
            case .cpu:
                if let previousSampleDate {
                    processes = ProcessResourceReader.activeCPUProcesses(
                        current: samples,
                        previous: previousSamples,
                        elapsed: now.timeIntervalSince(previousSampleDate),
                        limit: limit
                    )
                } else {
                    processes = ProcessResourceReader.topProcesses(samples, kind: kind, limit: limit)
                }
                previousSamples = Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
                previousSampleDate = now
            case .memory:
                processes = ProcessResourceReader.topProcesses(samples, kind: kind, limit: limit)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            processes = []
        }
    }
}

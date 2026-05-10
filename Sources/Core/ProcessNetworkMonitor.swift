import Foundation
import Darwin
import Observation

// ═══════════════════════════════════════════════════════════════
// MARK: - Process Network Monitor
// ═══════════════════════════════════════════════════════════════

/// Per-process network activity derived from `nettop` cumulative counters.
struct ProcessNetworkUsage: Identifiable, Equatable, Sendable {
    let pid: Int
    let name: String
    let downloadBytesPerSec: Int64
    let uploadBytesPerSec: Int64

    var id: Int { pid }
    var totalBytesPerSec: Int64 { downloadBytesPerSec + uploadBytesPerSec }
}

struct RawProcessNetworkSample: Equatable, Sendable {
    let pid: Int
    let name: String
    let downloadBytes: Int64
    let uploadBytes: Int64
}

struct ProcessNetworkSampleFrame: Equatable, Sendable {
    let samplesByPID: [Int: RawProcessNetworkSample]
    let timestamp: Date

    init(samples: [RawProcessNetworkSample], timestamp: Date = Date()) {
        self.samplesByPID = ProcessNetworkReader.aggregateSamplesByPID(samples)
        self.timestamp = timestamp
    }

    func isFresh(at date: Date = Date(), maxAge: TimeInterval) -> Bool {
        let age = date.timeIntervalSince(timestamp)
        return age >= 0 && age <= maxAge
    }
}

enum ProcessNetworkSortMode: String, CaseIterable, Sendable {
    case activity
    case download
    case upload
    case total

    var next: ProcessNetworkSortMode {
        switch self {
        case .activity: return .download
        case .download: return .upload
        case .upload: return .total
        case .total: return .activity
        }
    }
}

enum ProcessNetworkReader {
    static func readSamples(
        timeout: TimeInterval = 3,
        cancellationContext: ProcessCancellationContext? = nil
    ) throws -> [RawProcessNetworkSample] {
        try cancellationContext?.checkCancellation()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = [
            "-P", "-L", "1", "-n", "-x",
            "-k", "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch",
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["NSUnbufferedIO"] = "YES"
        environment["LC_ALL"] = "en_US.UTF-8"
        task.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let timeoutState = ProcessTimeoutState()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.standardInput = inputPipe

        try task.run()
        try cancellationContext?.register(task)
        defer { cancellationContext?.unregister(task) }
        try? inputPipe.fileHandleForWriting.close()

        let timeoutWork = DispatchWorkItem {
            guard task.isRunning else { return }
            timeoutState.markTimedOut()
            task.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if task.isRunning {
                kill(task.processIdentifier, SIGKILL)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        timeoutWork.cancel()
        try cancellationContext?.checkCancellation()

        try? inputPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        if timeoutState.didTimeOut {
            throw ProcessNetworkReaderError.nettopTimedOut
        }

        guard task.terminationStatus == 0 else {
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            throw ProcessNetworkReaderError.nettopFailed(errorText)
        }

        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            return []
        }
        return parseNettopOutput(output)
    }

    static func readSampleFrame(
        timeout: TimeInterval = 3,
        cancellationContext: ProcessCancellationContext? = nil
    ) throws -> ProcessNetworkSampleFrame {
        let samples = try readSamples(timeout: timeout, cancellationContext: cancellationContext)
        return ProcessNetworkSampleFrame(samples: samples)
    }

    static func parseNettopOutput(_ output: String) -> [RawProcessNetworkSample] {
        var samples: [RawProcessNetworkSample] = []
        var isHeader = true

        output.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                return
            }
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { return }
            guard let identity = parseProcessIdentity(String(columns[0])) else { return }
            let download = Int64(columns[1]) ?? 0
            let upload = Int64(columns[2]) ?? 0
            samples.append(RawProcessNetworkSample(
                pid: identity.pid,
                name: identity.name,
                downloadBytes: download,
                uploadBytes: upload
            ))
        }

        return samples
    }

    static func activeProcesses(
        current samples: [RawProcessNetworkSample],
        previous previousSamples: [Int: RawProcessNetworkSample],
        elapsed: TimeInterval,
        limit: Int,
        sortMode: ProcessNetworkSortMode = .activity
    ) -> [ProcessNetworkUsage] {
        sortedProcesses(
            activeProcesses(current: samples, previous: previousSamples, elapsed: elapsed),
            by: sortMode,
            limit: limit
        )
    }

    static func activeProcesses(
        current samples: [RawProcessNetworkSample],
        previous previousSamples: [Int: RawProcessNetworkSample],
        elapsed: TimeInterval
    ) -> [ProcessNetworkUsage] {
        let elapsed = max(elapsed, 0.1)
        return aggregateSamplesByPID(samples).values.compactMap { sample -> ProcessNetworkUsage? in
            guard let previous = previousSamples[sample.pid] else { return nil }
            let downloadDelta = max(Int64(0), sample.downloadBytes - previous.downloadBytes)
            let uploadDelta = max(Int64(0), sample.uploadBytes - previous.uploadBytes)
            guard downloadDelta > 0 || uploadDelta > 0 else { return nil }

            return ProcessNetworkUsage(
                pid: sample.pid,
                name: sample.name,
                downloadBytesPerSec: Int64(Double(downloadDelta) / elapsed),
                uploadBytesPerSec: Int64(Double(uploadDelta) / elapsed)
            )
        }
    }

    static func sortedProcesses(
        _ processes: [ProcessNetworkUsage],
        by sortMode: ProcessNetworkSortMode,
        limit: Int
    ) -> [ProcessNetworkUsage] {
        Array(processes.sorted { lhs, rhs in
            switch sortMode {
            case .activity:
                return compareActivity(lhs, rhs)
            case .download:
                return compare(lhs, rhs, primary: \.downloadBytesPerSec, secondary: \.uploadBytesPerSec)
            case .upload:
                return compare(lhs, rhs, primary: \.uploadBytesPerSec, secondary: \.downloadBytesPerSec)
            case .total:
                return compare(lhs, rhs, primary: \.totalBytesPerSec, secondary: \.downloadBytesPerSec)
            }
        }.prefix(limit))
    }

    private static func compareActivity(_ lhs: ProcessNetworkUsage, _ rhs: ProcessNetworkUsage) -> Bool {
        let lhsMax = max(lhs.downloadBytesPerSec, lhs.uploadBytesPerSec)
        let rhsMax = max(rhs.downloadBytesPerSec, rhs.uploadBytesPerSec)
        if lhsMax != rhsMax { return lhsMax > rhsMax }

        let lhsMin = min(lhs.downloadBytesPerSec, lhs.uploadBytesPerSec)
        let rhsMin = min(rhs.downloadBytesPerSec, rhs.uploadBytesPerSec)
        if lhsMin != rhsMin { return lhsMin > rhsMin }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func compare(
        _ lhs: ProcessNetworkUsage,
        _ rhs: ProcessNetworkUsage,
        primary: KeyPath<ProcessNetworkUsage, Int64>,
        secondary: KeyPath<ProcessNetworkUsage, Int64>
    ) -> Bool {
        let lhsPrimary = lhs[keyPath: primary]
        let rhsPrimary = rhs[keyPath: primary]
        if lhsPrimary != rhsPrimary { return lhsPrimary > rhsPrimary }

        let lhsSecondary = lhs[keyPath: secondary]
        let rhsSecondary = rhs[keyPath: secondary]
        if lhsSecondary != rhsSecondary { return lhsSecondary > rhsSecondary }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func parseProcessIdentity(_ raw: String) -> (pid: Int, name: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dotIndex = trimmed.lastIndex(of: ".") else { return nil }
        let pidText = trimmed[trimmed.index(after: dotIndex)...]
        guard let pid = Int(pidText) else { return nil }

        let rawName = trimmed[..<dotIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.isEmpty ? "\(pid)" : rawName
        return (pid, name)
    }

    static func aggregateSamplesByPID(_ samples: [RawProcessNetworkSample]) -> [Int: RawProcessNetworkSample] {
        samples.reduce(into: [:]) { result, sample in
            guard let existing = result[sample.pid] else {
                result[sample.pid] = sample
                return
            }

            result[sample.pid] = RawProcessNetworkSample(
                pid: sample.pid,
                name: existing.name.isEmpty ? sample.name : existing.name,
                downloadBytes: existing.downloadBytes + sample.downloadBytes,
                uploadBytes: existing.uploadBytes + sample.uploadBytes
            )
        }
    }
}

enum ProcessNetworkReaderError: LocalizedError {
    case nettopFailed(String)
    case nettopTimedOut

    var errorDescription: String? {
        switch self {
        case .nettopFailed(let message):
            return message.isEmpty ? "nettop failed" : message
        case .nettopTimedOut:
            return "nettop timed out"
        }
    }
}

private final class ProcessTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
}

@MainActor
@Observable
final class ProcessNetworkMonitor {
    private(set) var processes: [ProcessNetworkUsage] = []
    private(set) var isSampling: Bool = false
    private(set) var errorMessage: String?
    var sortMode: ProcessNetworkSortMode = .activity {
        didSet { refreshVisibleProcesses() }
    }

    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var previousSamples: [Int: RawProcessNetworkSample] = [:]
    @ObservationIgnored private var previousSampleDate: Date?
    @ObservationIgnored private var activeProcesses: [ProcessNetworkUsage] = []
    @ObservationIgnored private var limit: Int = 8
    @ObservationIgnored private var completedSampleCount = 0
    @ObservationIgnored private var cancellationContext: ProcessCancellationContext?

    deinit {
        sampleTask?.cancel()
        cancellationContext?.cancel()
    }

    func start(limit: Int = 8, sampleInterval: TimeInterval = 1) {
        self.limit = limit
        guard sampleTask == nil else { return }

        isSampling = true
        errorMessage = nil
        processes = []
        activeProcesses = []
        previousSamples.removeAll()
        previousSampleDate = nil
        completedSampleCount = 0

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
        activeProcesses = []
        previousSamples.removeAll()
        previousSampleDate = nil
        completedSampleCount = 0
    }

    private func sampleOnce(cancellationContext: ProcessCancellationContext) async {
        let result = await Task.detached(priority: .utility) {
            do {
                return Result<[RawProcessNetworkSample], Error>.success(
                    try ProcessNetworkReader.readSamples(cancellationContext: cancellationContext)
                )
            } catch {
                return Result<[RawProcessNetworkSample], Error>.failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let samples):
            errorMessage = nil
            completedSampleCount += 1
            apply(samples)
            if completedSampleCount >= 2 {
                isSampling = false
            }
        case .failure(let error):
            isSampling = false
            errorMessage = error.localizedDescription
            processes = []
            activeProcesses = []
        }
    }

    private func apply(_ samples: [RawProcessNetworkSample]) {
        let now = Date()
        let current = ProcessNetworkReader.aggregateSamplesByPID(samples)
        defer {
            previousSamples = current
            previousSampleDate = now
        }

        guard let previousDate = previousSampleDate, !previousSamples.isEmpty else {
            processes = []
            activeProcesses = []
            return
        }

        activeProcesses = ProcessNetworkReader.activeProcesses(
            current: samples,
            previous: previousSamples,
            elapsed: now.timeIntervalSince(previousDate)
        )
        refreshVisibleProcesses()
    }

    private func refreshVisibleProcesses() {
        processes = ProcessNetworkReader.sortedProcesses(activeProcesses, by: sortMode, limit: limit)
    }
}

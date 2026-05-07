import Foundation
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
    static func readSamples() throws -> [RawProcessNetworkSample] {
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
            throw ProcessNetworkReaderError.nettopFailed(errorText)
        }

        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            return []
        }
        return parseNettopOutput(output)
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
        return samples.compactMap { sample -> ProcessNetworkUsage? in
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
}

enum ProcessNetworkReaderError: LocalizedError {
    case nettopFailed(String)

    var errorDescription: String? {
        switch self {
        case .nettopFailed(let message):
            return message.isEmpty ? "nettop failed" : message
        }
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

    deinit {
        sampleTask?.cancel()
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
        activeProcesses = []
        previousSamples.removeAll()
        previousSampleDate = nil
    }

    private func sampleOnce() async {
        let result = await Task.detached(priority: .utility) {
            do {
                return Result<[RawProcessNetworkSample], Error>.success(try ProcessNetworkReader.readSamples())
            } catch {
                return Result<[RawProcessNetworkSample], Error>.failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let samples):
            errorMessage = nil
            apply(samples)
        case .failure(let error):
            errorMessage = error.localizedDescription
            processes = []
            activeProcesses = []
        }
    }

    private func apply(_ samples: [RawProcessNetworkSample]) {
        let now = Date()
        let current = Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
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

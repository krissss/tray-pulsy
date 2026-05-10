import Foundation
import Testing

@testable import TrayPulsy

@Suite("SpikeDiagnostics")
struct SpikeDiagnosticsTests {

    private func snapshot(
        cpu: Double = 0,
        memory: Double = 0,
        netIn: Double = 0,
        netOut: Double = 0,
        timestamp: Date = Date(),
        recordedMetrics: Set<SystemMonitor.MetricKind> = Set(SystemMonitor.MetricKind.allCases),
        recordedMetricItems: Set<MetricDisplayItem>? = nil
    ) -> MetricSnapshot {
        MetricSnapshot(
            cpuUsage: cpu,
            gpuUsage: 0,
            memoryUsage: memory,
            diskUsage: 0,
            netSpeedIn: netIn,
            netSpeedOut: netOut,
            timestamp: timestamp,
            recordedMetrics: recordedMetrics,
            recordedMetricItems: recordedMetricItems
        )
    }

    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpikeDiagnosticsTests-\(UUID().uuidString).bin")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func event(id: UUID = UUID(), metric: MetricSpikeKind = .cpu, timestamp: Date = Date()) -> MetricSpikeEvent {
        MetricSpikeEvent(
            id: id,
            metric: metric,
            previousValue: 10,
            currentValue: 80,
            delta: 70,
            timestamp: timestamp,
            processStatus: .ready,
            processes: [
                SpikeProcessSnapshot(
                    pid: 42,
                    name: "Example",
                    valueText: "12.0%",
                    fraction: 0.12,
                    metric: .cpu
                )
            ]
        )
    }

    @Test("first sample seeds detector without emitting a spike")
    func firstSampleSeedsDetector() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let result = detector.detect(
            snapshot: snapshot(cpu: 90),
            thresholds: ThresholdConfig.defaults,
            now: Date()
        )

        #expect(result == nil)
    }

    @Test("CPU jump above warning threshold emits spike")
    func cpuJumpEmitsSpike() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detect(
            snapshot: snapshot(cpu: 35, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let result = detector.detect(
            snapshot: snapshot(cpu: 82, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1)
        )

        #expect(result?.metric == .cpu)
        #expect(result?.previousValue == 35)
        #expect(result?.currentValue == 82)
        #expect(result?.delta == 47)
    }

    @Test("cooldown suppresses repeated spikes for the same metric")
    func cooldownSuppressesRepeatedSpikes() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detect(
            snapshot: snapshot(cpu: 30, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let first = detector.detect(
            snapshot: snapshot(cpu: 80, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1)
        )
        let second = detector.detect(
            snapshot: snapshot(cpu: 30, timestamp: now.addingTimeInterval(2)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(2)
        )
        let suppressed = detector.detect(
            snapshot: snapshot(cpu: 90, timestamp: now.addingTimeInterval(3)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(3)
        )

        #expect(first?.metric == .cpu)
        #expect(second == nil)
        #expect(suppressed == nil)
    }

    @Test("detector can defer cooldown until confirmation")
    func detectorCanDeferCooldown() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detect(
            snapshot: snapshot(netIn: 0, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let first = detector.detect(
            snapshot: snapshot(netIn: 1_200_000, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            shouldRecordCooldown: false
        )
        let second = detector.detect(
            snapshot: snapshot(netIn: 2_000_000, timestamp: now.addingTimeInterval(2)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(2),
            shouldRecordCooldown: false
        )

        #expect(first?.metric == .networkDown)
        #expect(second?.metric == .networkDown)

        detector.recordCooldown(for: .networkDown, at: now.addingTimeInterval(2))
        let suppressed = detector.detect(
            snapshot: snapshot(netIn: 3_000_000, timestamp: now.addingTimeInterval(3)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(3),
            shouldRecordCooldown: false
        )

        #expect(suppressed == nil)
    }

    @Test("detector skips pending metrics and returns the next candidate")
    func detectorSkipsExcludedMetrics() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detect(
            snapshot: snapshot(cpu: 30, memory: 40, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let result = detector.detect(
            snapshot: snapshot(cpu: 90, memory: 90, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            excludedMetrics: [.cpu],
            shouldRecordCooldown: false
        )

        #expect(result?.metric == .memory)
    }

    @Test("pending metrics keep their detection baseline for retry")
    func pendingMetricsKeepBaselineForRetry() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detectCandidates(
            snapshot: snapshot(cpu: 30, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let pending = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            excludedMetrics: [.cpu],
            shouldRecordCooldown: false
        )
        let retry = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, timestamp: now.addingTimeInterval(2)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(2),
            shouldRecordCooldown: false
        )

        #expect(pending.isEmpty)
        #expect(retry.first?.metric == .cpu)
        #expect(retry.first?.previousValue == 30)
        #expect(retry.first?.currentValue == 90)
    }

    @Test("new candidates can keep their baseline while awaiting confirmation")
    func newCandidatesCanKeepBaselineWhileAwaitingConfirmation() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detectCandidates(
            snapshot: snapshot(cpu: 30, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let first = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            shouldRecordCooldown: false,
            preserveCandidateBaselines: true
        )
        let retry = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, timestamp: now.addingTimeInterval(2)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(2),
            shouldRecordCooldown: false,
            preserveCandidateBaselines: true
        )

        #expect(first.first?.metric == .cpu)
        #expect(retry.first?.metric == .cpu)
        #expect(retry.first?.previousValue == 30)
        #expect(retry.first?.currentValue == 90)
    }

    @Test("detector returns every metric that spikes in the same sample")
    func detectorReturnsAllSameSampleSpikes() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detectCandidates(
            snapshot: snapshot(cpu: 30, memory: 40, netIn: 0, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let candidates = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, memory: 90, netIn: 1_200_000, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            shouldRecordCooldown: false
        )

        #expect(Set(candidates.map(\.metric)) == [.cpu, .memory, .networkDown])
    }

    @Test("detector limits candidates to monitored metrics")
    func detectorLimitsCandidatesToIncludedMetrics() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detectCandidates(
            snapshot: snapshot(cpu: 30, memory: 40, netIn: 0, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let candidates = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, memory: 90, netIn: 1_200_000, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            includedMetrics: [.memory],
            shouldRecordCooldown: false
        )

        #expect(candidates.map(\.metric) == [.memory])
    }

    @Test("spike kind monitoring follows direction-level metric items")
    func spikeKindMonitoringFollowsDirectionLevelMetricItems() {
        #expect(MetricSpikeKind.cpu.isMonitored(in: [.cpu]))
        #expect(MetricSpikeKind.networkDown.isMonitored(in: [.networkDown]))
        #expect(!MetricSpikeKind.networkDown.isMonitored(in: [.networkUp]))
        #expect(!MetricSpikeKind.networkUp.isMonitored(in: [.networkDown]))
    }

    @Test("detector ignores stale carry-forward baselines for re-enabled metrics")
    func detectorIgnoresUnrecordedBaselines() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detectCandidates(
            snapshot: snapshot(cpu: 20, timestamp: now, recordedMetrics: []),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let candidates = detector.detectCandidates(
            snapshot: snapshot(cpu: 90, timestamp: now.addingTimeInterval(1), recordedMetrics: [.cpu]),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            includedMetrics: [.cpu],
            shouldRecordCooldown: false
        )

        #expect(candidates.isEmpty)
    }

    @Test("detector ignores unrecorded network direction baselines")
    func detectorIgnoresUnrecordedNetworkDirectionBaselines() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detectCandidates(
            snapshot: snapshot(
                netIn: 0,
                netOut: 0,
                timestamp: now,
                recordedMetrics: [],
                recordedMetricItems: []
            ),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let candidates = detector.detectCandidates(
            snapshot: snapshot(
                netIn: 1_200_000,
                netOut: 500_000,
                timestamp: now.addingTimeInterval(1),
                recordedMetrics: [.network],
                recordedMetricItems: [.networkDown, .networkUp]
            ),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1),
            includedMetrics: [.networkDown, .networkUp],
            shouldRecordCooldown: false
        )

        #expect(candidates.isEmpty)
    }

    @Test("memory jump emits without requiring menu bar metric selection")
    func memoryJumpEmitsWithoutMetricSelection() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detect(
            snapshot: snapshot(memory: 40, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            now: now
        )
        let result = detector.detect(
            snapshot: snapshot(memory: 90, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            now: now.addingTimeInterval(1)
        )

        #expect(result?.metric == .memory)
    }

    @Test("configured spike delta controls detection sensitivity")
    func configuredSpikeDeltaControlsSensitivity() {
        var detector = MetricSpikeDetector()
        detector.cooldown = 30
        let now = Date()

        _ = detector.detect(
            snapshot: snapshot(cpu: 40, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig(cpu: 45, memory: 8, networkDown: 500_000, networkUp: 250_000),
            now: now
        )
        let suppressed = detector.detect(
            snapshot: snapshot(cpu: 80, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig(cpu: 45, memory: 8, networkDown: 500_000, networkUp: 250_000),
            now: now.addingTimeInterval(1)
        )

        #expect(suppressed == nil)

        detector.reset()
        _ = detector.detect(
            snapshot: snapshot(cpu: 40, timestamp: now),
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig(cpu: 20, memory: 8, networkDown: 500_000, networkUp: 250_000),
            now: now
        )
        let detected = detector.detect(
            snapshot: snapshot(cpu: 80, timestamp: now.addingTimeInterval(1)),
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig(cpu: 20, memory: 8, networkDown: 500_000, networkUp: 250_000),
            now: now.addingTimeInterval(1)
        )

        #expect(detected?.metric == .cpu)
    }

    @Test("confirmation ignores metrics that fell back below the spike rule")
    func confirmationIgnoresRecoveredMetric() {
        let now = Date()
        let candidate = MetricSpikeCandidate(
            metric: .cpu,
            previousValue: 30,
            currentValue: 90,
            delta: 60,
            timestamp: now,
            score: 2
        )

        let confirmation = MetricSpikeProcessSampler.confirmedSpike(
            candidate: candidate,
            currentValue: 45,
            timestamp: now.addingTimeInterval(1),
            processes: [],
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig.defaults
        )

        #expect(confirmation == nil)
    }

    @Test("confirmation ignores metrics whose confirmed delta fell below the spike rule")
    func confirmationIgnoresRecoveredDelta() {
        let now = Date()
        let candidate = MetricSpikeCandidate(
            metric: .cpu,
            previousValue: 30,
            currentValue: 90,
            delta: 60,
            timestamp: now,
            score: 2
        )

        let confirmation = MetricSpikeProcessSampler.confirmedSpike(
            candidate: candidate,
            currentValue: 50,
            timestamp: now.addingTimeInterval(1),
            processes: [],
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig.defaults
        )

        #expect(confirmation == nil)
    }

    @Test("confirmation records the confirmed value together with process attribution")
    func confirmationRecordsConfirmedValueWithProcesses() {
        let now = Date()
        let candidate = MetricSpikeCandidate(
            metric: .memory,
            previousValue: 70,
            currentValue: 90,
            delta: 20,
            timestamp: now,
            score: 2
        )
        let processes = [
            SpikeProcessSnapshot(
                pid: 42,
                name: "Renderer",
                valueText: "1 GB 12.0%",
                fraction: 0.12,
                metric: .memory
            ),
        ]

        let confirmation = MetricSpikeProcessSampler.confirmedSpike(
            candidate: candidate,
            currentValue: 84,
            timestamp: now.addingTimeInterval(1),
            processes: processes,
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig.defaults
        )

        #expect(confirmation?.candidate.currentValue == 84)
        #expect(confirmation?.candidate.previousValue == 70)
        #expect(confirmation?.candidate.delta == 14)
        #expect(confirmation?.processes.first?.pid == 42)
    }

    @Test("network snapshots use baseline window for attribution")
    func networkSnapshotsUseBaselineWindow() {
        let previous = [
            10: RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_000, uploadBytes: 100),
            11: RawProcessNetworkSample(pid: 11, name: "Uploader", downloadBytes: 200, uploadBytes: 500),
        ]
        let current = [
            RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 3_000, uploadBytes: 100),
            RawProcessNetworkSample(pid: 11, name: "Uploader", downloadBytes: 200, uploadBytes: 2_500),
        ]

        let down = MetricSpikeProcessSampler.networkSnapshots(
            current: current,
            previous: previous,
            elapsed: 2,
            metric: .networkDown,
            limit: 2,
            sortMode: .download
        )
        let up = MetricSpikeProcessSampler.networkSnapshots(
            current: current,
            previous: previous,
            elapsed: 2,
            metric: .networkUp,
            limit: 2,
            sortMode: .upload
        )

        #expect(down.first?.pid == 10)
        #expect(down.first?.valueText == "↓1K/s")
        #expect(up.first?.pid == 11)
        #expect(up.first?.valueText == "↑1K/s")
    }

    @Test("network confirmation ignores windows below spike rule")
    func networkConfirmationIgnoresBelowRuleWindow() async {
        let now = Date()
        let candidate = MetricSpikeCandidate(
            metric: .networkDown,
            previousValue: 0,
            currentValue: 1_200_000,
            delta: 1_200_000,
            timestamp: now,
            score: 2
        )
        let baseline = ProcessNetworkSampleFrame(
            samples: [
                RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_000, uploadBytes: 0),
            ],
            timestamp: now
        )
        let current = ProcessNetworkSampleFrame(
            samples: [
                RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_100, uploadBytes: 0),
            ],
            timestamp: now.addingTimeInterval(1)
        )

        let confirmation = MetricSpikeProcessSampler.confirmedNetworkSpike(
            candidate: candidate,
            current: current,
            baseline: baseline,
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig.defaults,
            limit: 5
        )

        #expect(confirmation == nil)
    }

    @Test("network confirmation records confirmed window value")
    func networkConfirmationRecordsConfirmedWindowValue() async {
        let now = Date()
        let candidate = MetricSpikeCandidate(
            metric: .networkDown,
            previousValue: 0,
            currentValue: 1_200_000,
            delta: 1_200_000,
            timestamp: now,
            score: 2
        )
        let baseline = ProcessNetworkSampleFrame(
            samples: [
                RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_000, uploadBytes: 0),
            ],
            timestamp: now
        )
        let current = ProcessNetworkSampleFrame(
            samples: [
                RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_201_000, uploadBytes: 0),
            ],
            timestamp: now.addingTimeInterval(1)
        )

        let confirmation = MetricSpikeProcessSampler.confirmedNetworkSpike(
            candidate: candidate,
            current: current,
            baseline: baseline,
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig.defaults,
            limit: 5
        )

        #expect(confirmation?.candidate.currentValue == 1_200_000)
        #expect(confirmation?.candidate.delta == 1_200_000)
        #expect(confirmation?.processes.first?.pid == 10)
    }

    @Test("network confirmation recomputes delta from original baseline")
    func networkConfirmationRecomputesDeltaFromOriginalBaseline() async {
        let now = Date()
        let candidate = MetricSpikeCandidate(
            metric: .networkDown,
            previousValue: 900_000,
            currentValue: 1_500_000,
            delta: 600_000,
            timestamp: now,
            score: 2
        )
        let baseline = ProcessNetworkSampleFrame(
            samples: [
                RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_000, uploadBytes: 0),
            ],
            timestamp: now
        )
        let current = ProcessNetworkSampleFrame(
            samples: [
                RawProcessNetworkSample(pid: 10, name: "Downloader", downloadBytes: 1_501_000, uploadBytes: 0),
            ],
            timestamp: now.addingTimeInterval(1)
        )

        let confirmation = MetricSpikeProcessSampler.confirmedNetworkSpike(
            candidate: candidate,
            current: current,
            baseline: baseline,
            thresholds: ThresholdConfig.defaults,
            spikeDeltas: SpikeDeltaConfig.defaults,
            limit: 5
        )

        #expect(confirmation?.candidate.currentValue == 1_500_000)
        #expect(confirmation?.candidate.delta == 600_000)
        #expect(confirmation?.candidate.previousValue == 900_000)
    }

    @Test("spike history persists and reloads newest events")
    func spikeHistoryPersistsAndReloads() {
        let url = tempURL()
        defer { cleanup(url) }
        let now = Date()
        let history = MetricSpikeHistory(limit: 2, storageURL: url)

        history.record(event(metric: .cpu, timestamp: now.addingTimeInterval(-2)))
        history.record(event(metric: .memory, timestamp: now.addingTimeInterval(-1)))
        history.record(event(metric: .networkDown, timestamp: now))
        history.flush()

        let reloaded = MetricSpikeHistory(limit: 2, storageURL: url)
        #expect(reloaded.events.map(\.metric) == [.networkDown, .memory])
        #expect(reloaded.events.first?.processes.first?.name == "Example")
    }

    @Test("spike history limit changes trim retained events")
    func spikeHistoryLimitChangesTrimEvents() {
        let url = tempURL()
        defer { cleanup(url) }
        let history = MetricSpikeHistory(limit: 4, storageURL: url)

        history.record(event(metric: .cpu))
        history.record(event(metric: .memory))
        history.record(event(metric: .networkDown))
        history.reconfigure(limit: 2)

        #expect(history.events.map(\.metric) == [.networkDown, .memory])
    }

    @Test("sampling spike events persist as unavailable")
    func samplingSpikeEventsPersistAsUnavailable() {
        let url = tempURL()
        defer { cleanup(url) }
        let history = MetricSpikeHistory(limit: 2, storageURL: url)
        var sampling = event()
        sampling.processStatus = .sampling

        history.record(sampling)
        history.flush()

        let reloaded = MetricSpikeHistory(limit: 2, storageURL: url)
        #expect(reloaded.events.first?.processStatus == .unavailable)
    }
}

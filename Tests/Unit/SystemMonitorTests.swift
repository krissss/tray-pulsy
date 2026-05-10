import Testing

@testable import TrayPulsy

@Suite("SystemMonitor")
struct SystemMonitorTests {

    @Test("CPU re-enable frame seeds baseline without recording history")
    func cpuReenableFrameIsNotRecorded() {
        let resetMetrics = SystemMonitor.metricsNeedingBaselineReset(
            enabledMetrics: [.cpu, .memory],
            previousTickMetrics: [.memory],
            hasPreviousTickMetrics: true,
            metricsDisabledSinceLastTick: []
        )
        let scope = SystemMonitor.historyRecordingScope(
            enabledMetrics: [.cpu, .memory],
            recordedMetrics: [.cpu, .memory],
            recordedMetricItems: [.cpu, .memory],
            resetMetrics: resetMetrics
        )

        #expect(scope.metrics == [.memory])
        #expect(scope.metricItems == [.memory])
    }

    @Test("CPU re-enable within same tick still resets baseline")
    func cpuReenableWithinSameTickStillResetsBaseline() {
        let resetMetrics = SystemMonitor.metricsNeedingBaselineReset(
            enabledMetrics: [.cpu, .memory],
            previousTickMetrics: [.cpu, .memory],
            hasPreviousTickMetrics: true,
            metricsDisabledSinceLastTick: [.cpu]
        )
        let scope = SystemMonitor.historyRecordingScope(
            enabledMetrics: [.cpu, .memory],
            recordedMetrics: [.cpu, .memory],
            recordedMetricItems: [.cpu, .memory],
            resetMetrics: resetMetrics
        )

        #expect(resetMetrics == [.cpu])
        #expect(scope.metrics == [.memory])
        #expect(scope.metricItems == [.memory])
    }

    @Test("Initial CPU frame remains recorded after startup seeding")
    func initialCPUFrameRemainsRecorded() {
        let resetMetrics = SystemMonitor.metricsNeedingBaselineReset(
            enabledMetrics: [.cpu],
            previousTickMetrics: [],
            hasPreviousTickMetrics: false,
            metricsDisabledSinceLastTick: []
        )
        let scope = SystemMonitor.historyRecordingScope(
            enabledMetrics: [.cpu],
            recordedMetrics: [.cpu],
            recordedMetricItems: [.cpu],
            resetMetrics: resetMetrics
        )

        #expect(resetMetrics.isEmpty)
        #expect(scope.metrics == [.cpu])
        #expect(scope.metricItems == [.cpu])
    }

    @Test("Network re-enable frame is not recorded")
    func networkReenableFrameIsNotRecorded() {
        let resetMetrics = SystemMonitor.metricsNeedingBaselineReset(
            enabledMetrics: [.network],
            previousTickMetrics: [.cpu],
            hasPreviousTickMetrics: true,
            metricsDisabledSinceLastTick: []
        )
        let scope = SystemMonitor.historyRecordingScope(
            enabledMetrics: [.network],
            recordedMetrics: [.network],
            recordedMetricItems: [.networkDown, .networkUp],
            resetMetrics: resetMetrics
        )

        #expect(resetMetrics == [.network])
        #expect(scope.metrics.isEmpty)
        #expect(scope.metricItems.isEmpty)
    }

    @Test("Network re-enable within same tick still resets baseline")
    func networkReenableWithinSameTickStillResetsBaseline() {
        let resetMetrics = SystemMonitor.metricsNeedingBaselineReset(
            enabledMetrics: [.network],
            previousTickMetrics: [.network],
            hasPreviousTickMetrics: true,
            metricsDisabledSinceLastTick: [.network]
        )
        let scope = SystemMonitor.historyRecordingScope(
            enabledMetrics: [.network],
            recordedMetrics: [.network],
            recordedMetricItems: [.networkDown, .networkUp],
            resetMetrics: resetMetrics
        )

        #expect(resetMetrics == [.network])
        #expect(scope.metrics.isEmpty)
        #expect(scope.metricItems.isEmpty)
    }

    @Test("Stable enabled metrics remain recorded")
    func stableEnabledMetricsRemainRecorded() {
        let resetMetrics = SystemMonitor.metricsNeedingBaselineReset(
            enabledMetrics: [.cpu, .network],
            previousTickMetrics: [.cpu, .network],
            hasPreviousTickMetrics: true,
            metricsDisabledSinceLastTick: []
        )
        let scope = SystemMonitor.historyRecordingScope(
            enabledMetrics: [.cpu, .network],
            recordedMetrics: [.cpu, .network],
            recordedMetricItems: [.cpu, .networkDown, .networkUp],
            resetMetrics: resetMetrics
        )

        #expect(resetMetrics.isEmpty)
        #expect(scope.metrics == [.cpu, .network])
        #expect(scope.metricItems == [.cpu, .networkDown, .networkUp])
    }

    @Test("CPU re-enable frame publishes zero for live fallback")
    func cpuReenableFramePublishesZero() {
        let value = SystemMonitor.publishedCPUUsage(sampledValue: 58, needsBaselineReset: true)

        #expect(value == 0)
    }

    @Test("Stable CPU frame publishes sampled value")
    func stableCPUFramePublishesSampledValue() {
        let value = SystemMonitor.publishedCPUUsage(sampledValue: 58, needsBaselineReset: false)

        #expect(value == 58)
    }

    @Test("CPU live value clears when disabled")
    func cpuLiveValueClearsWhenDisabled() {
        let metrics = SystemMonitor.liveMetricsToClearAfterEnabledMetricsChange(
            oldEnabledMetrics: [.cpu, .memory],
            newEnabledMetrics: [.memory],
            metricsDisabledSinceLastTick: [.cpu]
        )

        #expect(metrics == [.cpu])
    }

    @Test("CPU live value clears when re-enabled before next tick")
    func cpuLiveValueClearsWhenReenabledBeforeNextTick() {
        let metrics = SystemMonitor.liveMetricsToClearAfterEnabledMetricsChange(
            oldEnabledMetrics: [.memory],
            newEnabledMetrics: [.cpu, .memory],
            metricsDisabledSinceLastTick: [.cpu]
        )

        #expect(metrics == [.cpu])
    }

    @Test("Network live value clears when disabled")
    func networkLiveValueClearsWhenDisabled() {
        let metrics = SystemMonitor.liveMetricsToClearAfterEnabledMetricsChange(
            oldEnabledMetrics: [.network, .memory],
            newEnabledMetrics: [.memory],
            metricsDisabledSinceLastTick: [.network]
        )

        #expect(metrics == [.network])
    }

    @Test("Stable live metrics are not cleared")
    func stableLiveMetricsAreNotCleared() {
        let metrics = SystemMonitor.liveMetricsToClearAfterEnabledMetricsChange(
            oldEnabledMetrics: [.cpu, .network],
            newEnabledMetrics: [.cpu, .network],
            metricsDisabledSinceLastTick: []
        )

        #expect(metrics.isEmpty)
    }

    @Test("Direction-level recording changes invalidate in-flight samples")
    func directionLevelRecordingChangesInvalidateInFlightSamples() {
        let changed = SystemMonitor.metricConfigurationChanged(
            oldEnabledMetrics: [.network],
            newEnabledMetrics: [.network],
            oldRecordedMetrics: [.network],
            newRecordedMetrics: [.network],
            oldRecordedMetricItems: [.networkDown, .networkUp],
            newRecordedMetricItems: [.networkUp]
        )

        #expect(changed)
    }

    @Test("Identical metric configuration does not invalidate samples")
    func identicalMetricConfigurationDoesNotInvalidateSamples() {
        let changed = SystemMonitor.metricConfigurationChanged(
            oldEnabledMetrics: [.cpu, .network],
            newEnabledMetrics: [.cpu, .network],
            oldRecordedMetrics: [.cpu, .network],
            newRecordedMetrics: [.cpu, .network],
            oldRecordedMetricItems: [.cpu, .networkDown],
            newRecordedMetricItems: [.cpu, .networkDown]
        )

        #expect(!changed)
    }
}

import Defaults
import SwiftUI

struct PerformanceDetail: View {
    @Default(.speedSource) private var speedSource
    @Default(.fpsLimit) private var fpsLimit
    @Default(.sampleInterval) private var sampleInterval
    @Default(.historyDuration) private var historyDuration
    @Default(.spikeEventLimit) private var spikeEventLimit

    var body: some View {
        SettingsFormPage {
            Section {
                Picker(selection: $speedSource) {
                    ForEach(SpeedSource.allCases, id: \.rawValue) { src in
                        Label(src.label, systemImage: src.systemImage).tag(src)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.perfSourceLabel,
                        systemImage: "speedometer",
                        color: .blue
                    )
                }
            } header: {
                Text(L10n.perfSourceHeader)
            } footer: {
                Text(L10n.perfSourceFooter)
            }

            Section {
                Picker(selection: $fpsLimit) {
                    ForEach(FPSLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.perfFpsLabel,
                        systemImage: "gauge.with.dots.needle.33percent",
                        color: .green
                    )
                }
            } header: {
                Text(L10n.perfFpsHeader)
            } footer: {
                Text(L10n.perfFpsFooter)
            }

            Section {
                Picker(selection: $sampleInterval) {
                    ForEach(SampleInterval.allCases, id: \.rawValue) { si in
                        Text(si.displayName).tag(si)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.perfSampleLabel,
                        systemImage: "clock.arrow.2.circlepath",
                        color: .orange
                    )
                }
            } header: {
                Text(L10n.perfSampleHeader)
            } footer: {
                Text(L10n.perfSampleFooter)
            }

            Section {
                Picker(selection: $historyDuration) {
                    ForEach(HistoryDuration.allCases, id: \.rawValue) { dur in
                        Text(dur.displayName).tag(dur)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.perfHistoryLabel,
                        systemImage: "chart.xyaxis.line",
                        color: .purple
                    )
                }
            } header: {
                Text(L10n.perfHistoryHeader)
            } footer: {
                Text(L10n.perfHistoryFooter)
            }

            Section {
                Picker(selection: $spikeEventLimit) {
                    ForEach(SpikeEventLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.perfSpikeLimitLabel,
                        systemImage: "waveform.path.ecg",
                        color: .pink
                    )
                }
            } header: {
                Text(L10n.perfSpikeLimitHeader)
            } footer: {
                Text(L10n.perfSpikeLimitFooter)
            }
        }
    }
}

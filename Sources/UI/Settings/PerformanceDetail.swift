import Defaults
import SwiftUI

struct PerformanceDetail: View {
    @Default(.speedSource) private var speedSource
    @Default(.fpsLimit) private var fpsLimit
    @Default(.sampleInterval) private var sampleInterval
    @Default(.historyDuration) private var historyDuration

    var body: some View {
        GlassEffectContainer {
            Form {
                Section {
                    Picker(selection: $speedSource, label: Label(L10n.perfSourceLabel, systemImage: "speedometer")) {
                        ForEach(SpeedSource.allCases, id: \.rawValue) { src in
                            Label(src.label, systemImage: src.systemImage).tag(src)
                        }
                    }
                } header: {
                    Text(L10n.perfSourceHeader)
                } footer: {
                    Text(L10n.perfSourceFooter)
                }

                Section {
                    Picker(selection: $fpsLimit, label: Label(L10n.perfFpsLabel, systemImage: "gauge.with.dots.needle.33percent")) {
                        ForEach(FPSLimit.allCases, id: \.rawValue) { limit in
                            Text(limit.displayName).tag(limit)
                        }
                    }
                } header: {
                    Text(L10n.perfFpsHeader)
                } footer: {
                    Text(L10n.perfFpsFooter)
                }

                Section {
                    Picker(selection: $sampleInterval, label: Label(L10n.perfSampleLabel, systemImage: "clock.arrow.2.circlepath")) {
                        ForEach(SampleInterval.allCases, id: \.rawValue) { si in
                            Text(si.displayName).tag(si)
                        }
                    }
                } header: {
                    Text(L10n.perfSampleHeader)
                } footer: {
                    Text(L10n.perfSampleFooter)
                }

                Section {
                    Picker(selection: $historyDuration, label: Label(L10n.perfHistoryLabel, systemImage: "chart.xyaxis.line")) {
                        ForEach(HistoryDuration.allCases, id: \.rawValue) { dur in
                            Text(dur.displayName).tag(dur)
                        }
                    }
                } header: {
                    Text(L10n.perfHistoryHeader)
                } footer: {
                    Text(L10n.perfHistoryFooter)
                }
            }
            .formStyle(.grouped)
        }
    }
}

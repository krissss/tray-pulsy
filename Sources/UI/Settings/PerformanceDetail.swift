import Defaults
import SwiftUI

struct PerformanceDetail: View {
    @Default(.speedSource) private var speedSource
    @Default(.fpsLimit) private var fpsLimit
    @Default(.sampleInterval) private var sampleInterval

    var body: some View {
        Form {
            Section {
                Picker(selection: $speedSource, label: Label("动画驱动", systemImage: "speedometer")) {
                    ForEach(SpeedSource.allCases, id: \.rawValue) { src in
                        Label(src.label, systemImage: src.systemImage).tag(src)
                    }
                }
            } header: {
                Text("速度来源")
            } footer: {
                Text("猫咪动画速度将跟随所选指标实时变化。")
            }

            Section {
                Picker(selection: $fpsLimit, label: Label("最高帧率", systemImage: "gauge.with.dots.needle.33percent")) {
                    ForEach(FPSLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
            } header: {
                Text("帧率控制")
            } footer: {
                Text("限制最高帧率以降低 CPU 占用。")
            }

            Section {
                Picker(selection: $sampleInterval, label: Label("采样频率", systemImage: "clock.arrow.2.circlepath")) {
                    ForEach(SampleInterval.allCases, id: \.rawValue) { si in
                        Text(si.displayName).tag(si)
                    }
                }
            } header: {
                Text("数据采样")
            } footer: {
                Text("间隔越短，动画响应越快，但 CPU 占用略高。")
            }
        }
        .formStyle(.grouped)
    }
}

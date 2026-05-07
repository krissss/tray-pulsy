import Testing

@testable import TrayPulsy

@Suite("ProcessNetworkMonitor")
struct ProcessNetworkMonitorTests {

    @Test("parse nettop output extracts pid, name and byte counters")
    func parseNettopOutput() {
        let output = """
        ,bytes_in,bytes_out,
        launchd.1,0,0,
        Microsoft Edge .709,282346246,1431971,
        Google Chrome H.74009,8419,2025,
        """

        let samples = ProcessNetworkReader.parseNettopOutput(output)

        #expect(samples.count == 3)
        #expect(samples[1] == RawProcessNetworkSample(
            pid: 709,
            name: "Microsoft Edge",
            downloadBytes: 282_346_246,
            uploadBytes: 1_431_971
        ))
        #expect(samples[2].pid == 74009)
        #expect(samples[2].name == "Google Chrome H")
    }

    @Test("active process diff clamps negative counters and sorts by activity")
    func activeProcessDiff() {
        let previous = [
            10: RawProcessNetworkSample(pid: 10, name: "Alpha", downloadBytes: 1_000, uploadBytes: 500),
            11: RawProcessNetworkSample(pid: 11, name: "Beta", downloadBytes: 8_000, uploadBytes: 8_000),
            12: RawProcessNetworkSample(pid: 12, name: "Gamma", downloadBytes: 500, uploadBytes: 500),
        ]
        let current = [
            RawProcessNetworkSample(pid: 10, name: "Alpha", downloadBytes: 3_000, uploadBytes: 500),
            RawProcessNetworkSample(pid: 11, name: "Beta", downloadBytes: 7_000, uploadBytes: 8_200),
            RawProcessNetworkSample(pid: 12, name: "Gamma", downloadBytes: 1_000, uploadBytes: 4_500),
        ]

        let active = ProcessNetworkReader.activeProcesses(
            current: current,
            previous: previous,
            elapsed: 2,
            limit: 2
        )

        #expect(active.map(\.pid) == [12, 10])
        #expect(active[0].downloadBytesPerSec == 250)
        #expect(active[0].uploadBytesPerSec == 2_000)
        #expect(active[1].downloadBytesPerSec == 1_000)
        #expect(active[1].uploadBytesPerSec == 0)
    }

    @Test("sort modes reorder by download, upload and total")
    func sortModes() {
        let processes = [
            ProcessNetworkUsage(pid: 1, name: "Download", downloadBytesPerSec: 5_000, uploadBytesPerSec: 0),
            ProcessNetworkUsage(pid: 2, name: "Upload", downloadBytesPerSec: 0, uploadBytesPerSec: 6_000),
            ProcessNetworkUsage(pid: 3, name: "Balanced", downloadBytesPerSec: 3_500, uploadBytesPerSec: 3_500),
        ]

        #expect(ProcessNetworkReader.sortedProcesses(processes, by: .download, limit: 3).map(\.pid) == [1, 3, 2])
        #expect(ProcessNetworkReader.sortedProcesses(processes, by: .upload, limit: 3).map(\.pid) == [2, 3, 1])
        #expect(ProcessNetworkReader.sortedProcesses(processes, by: .total, limit: 3).map(\.pid) == [3, 2, 1])
        #expect(ProcessNetworkReader.sortedProcesses(processes, by: .activity, limit: 3).map(\.pid) == [2, 1, 3])
    }
}

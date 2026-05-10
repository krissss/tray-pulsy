import Foundation
import Testing

@testable import TrayPulsy

@Suite("ProcessResourceMonitor")
struct ProcessResourceMonitorTests {

    @Test("parse ps output extracts normalized cpu memory and command name")
    func parsePSOutput() {
        let output = """
            101   0.0   0:01.20  12000 /usr/libexec/configd
          74001  12.5  1:02:03.50 512000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          74009   1.2   2-00:00:00.00 128000 Google Chrome Helper
        """

        let samples = ProcessResourceReader.parsePSOutput(
            output,
            processorCount: 10,
            totalMemoryBytes: 1_073_741_824
        )

        #expect(samples.count == 3)
        #expect(samples[0].pid == 101)
        #expect(samples[0].name == "configd")
        #expect(samples[0].cpuPercent == 0)
        #expect(samples[0].memoryBytes == 12_000 * 1024)
        #expect(abs(samples[0].memoryPercent - 1.1444) < 0.0001)
        #expect(samples[0].cpuTime == 1.2)
        #expect(samples[1].pid == 74001)
        #expect(samples[1].name == "Google Chrome")
        #expect(abs(samples[1].cpuPercent - 1.25) < 0.0001)
        #expect(samples[1].memoryBytes == 512_000 * 1024)
        #expect(abs(samples[1].memoryPercent - 48.8281) < 0.0001)
        #expect(samples[1].cpuTime == 3_723.5)
        #expect(samples[2].name == "Google Chrome Helper")
        #expect(abs(samples[2].cpuPercent - 0.12) < 0.0001)
        #expect(samples[2].cpuTime == 172_800)
    }

    @Test("sample frame indexes rows and keeps timestamp")
    func sampleFrameIndexesRowsAndTimestamp() {
        let now = Date()
        let frame = ProcessResourceSampleFrame(
            samples: [
                ProcessResourceUsage(pid: 1, name: "A", cpuPercent: 1, memoryBytes: 100, cpuTime: 10),
                ProcessResourceUsage(pid: 2, name: "B", cpuPercent: 2, memoryBytes: 200, cpuTime: 20),
            ],
            timestamp: now
        )

        #expect(frame.samples.count == 2)
        #expect(frame.samplesByPID[1]?.name == "A")
        #expect(frame.samplesByPID[2]?.cpuTime == 20)
        #expect(frame.timestamp == now)
    }

    @Test("top processes sort by cpu and memory")
    func topProcessesSortByKind() {
        let samples = [
            ProcessResourceUsage(pid: 1, name: "LowCPU", cpuPercent: 1.0, memoryBytes: 900),
            ProcessResourceUsage(pid: 2, name: "HighMemory", cpuPercent: 0.5, memoryBytes: 9_000),
            ProcessResourceUsage(pid: 3, name: "HighCPU", cpuPercent: 42.0, memoryBytes: 100),
            ProcessResourceUsage(pid: 4, name: "Idle", cpuPercent: 0, memoryBytes: 1_000),
        ]

        let cpu = ProcessResourceReader.topProcesses(samples, kind: .cpu, limit: 3)
        let memory = ProcessResourceReader.topProcesses(samples, kind: .memory, limit: 3)

        #expect(cpu.map(\.pid) == [3, 1, 2])
        #expect(memory.map(\.pid) == [2, 4, 1])
    }

    @Test("active CPU processes sort by recent CPU time delta")
    func activeCPUProcessesSortByRecentDelta() {
        let previous = [
            1: ProcessResourceUsage(pid: 1, name: "Idle", cpuPercent: 0, memoryBytes: 100, cpuTime: 10),
            2: ProcessResourceUsage(pid: 2, name: "Burst", cpuPercent: 0, memoryBytes: 100, cpuTime: 20),
            3: ProcessResourceUsage(pid: 3, name: "Steady", cpuPercent: 0, memoryBytes: 100, cpuTime: 30),
        ]
        let current = [
            ProcessResourceUsage(pid: 1, name: "Idle", cpuPercent: 0, memoryBytes: 100, cpuTime: 10),
            ProcessResourceUsage(pid: 2, name: "Burst", cpuPercent: 0, memoryBytes: 100, cpuTime: 22),
            ProcessResourceUsage(pid: 3, name: "Steady", cpuPercent: 0, memoryBytes: 100, cpuTime: 31),
        ]

        let processes = ProcessResourceReader.activeCPUProcesses(
            current: current,
            previous: previous,
            elapsed: 1,
            processorCount: 4,
            limit: 2
        )

        #expect(processes.map(\.pid) == [2, 3])
        #expect(processes[0].cpuPercent == 50)
        #expect(processes[1].cpuPercent == 25)
    }
}

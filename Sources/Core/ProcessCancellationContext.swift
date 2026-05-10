import Darwin
import Foundation

final class ProcessCancellationContext: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var processes: [Process] = []

    func checkCancellation() throws {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            throw CancellationError()
        }
    }

    func register(_ process: Process) throws {
        lock.lock()
        let cancelled = isCancelled
        if !cancelled {
            processes.append(process)
        }
        lock.unlock()

        if cancelled {
            terminate(process)
            throw CancellationError()
        }
    }

    func unregister(_ process: Process) {
        lock.lock()
        processes.removeAll { $0 === process }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let runningProcesses = processes
        lock.unlock()

        runningProcesses.forEach(terminate)
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

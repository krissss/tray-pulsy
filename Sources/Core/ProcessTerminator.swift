import AppKit
import Darwin
import Foundation

enum ProcessTerminator {
    @discardableResult
    static func terminate(pid: Int) -> Result<Void, ProcessTerminationError> {
        guard pid > 0 else { return .failure(.invalidPID) }
        guard pid != Int(ProcessInfo.processInfo.processIdentifier) else {
            return .failure(.currentProcess)
        }

        if let app = NSRunningApplication(processIdentifier: pid_t(pid)), app.terminate() {
            return .success(())
        }

        if Darwin.kill(pid_t(pid), SIGTERM) == 0 {
            return .success(())
        }

        return .failure(.signalFailed(errno))
    }
}

enum ProcessTerminationError: LocalizedError, Equatable {
    case invalidPID
    case currentProcess
    case signalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPID:
            return "Invalid process identifier."
        case .currentProcess:
            return "TrayPulsy cannot terminate itself from the process list."
        case .signalFailed(let errorCode):
            return String(cString: strerror(errorCode))
        }
    }
}

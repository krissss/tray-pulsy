import Foundation
import IOKit
import IOKit.pwr_mgt

protocol PowerAssertionControlling {
    func createNoIdleSleepAssertion(reason: String) throws -> IOPMAssertionID
    func releaseAssertion(_ assertionID: IOPMAssertionID)
}

enum PowerAssertionError: Error, Equatable {
    case createFailed(IOReturn)
}

struct IOKitPowerAssertionController: PowerAssertionControlling {
    func createNoIdleSleepAssertion(reason: String) throws -> IOPMAssertionID {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.createFailed(result)
        }
        return assertionID
    }

    func releaseAssertion(_ assertionID: IOPMAssertionID) {
        IOPMAssertionRelease(assertionID)
    }
}

@MainActor
final class SleepPreventer {
    typealias ExpirationHandler = () -> Void

    private let controller: PowerAssertionControlling
    private let reason: String
    private let now: () -> Date
    private let logError: (Error) -> Void
    private var assertionID: IOPMAssertionID?
    private var expirationTimer: Timer?
    private var expirationHandler: ExpirationHandler?

    init(
        controller: PowerAssertionControlling = IOKitPowerAssertionController(),
        reason: String = "\(AppConstants.appName) keep awake",
        now: @escaping () -> Date = Date.init,
        logError: @escaping (Error) -> Void = { print("[KeepAwake] assertion error: \($0)") }
    ) {
        self.controller = controller
        self.reason = reason
        self.now = now
        self.logError = logError
    }

    var isActive: Bool {
        assertionID != nil
    }

    func apply(enabled: Bool, expiresAt: Date?, onExpired: @escaping ExpirationHandler) {
        expirationHandler = onExpired

        guard enabled else {
            stop()
            return
        }

        if let expiresAt, expiresAt <= now() {
            expire()
            return
        }

        acquireIfNeeded()
        scheduleExpiration(until: expiresAt)
    }

    func suspend() {
        invalidateExpirationTimer()
        releaseAssertionIfNeeded()
    }

    func stop() {
        expirationHandler = nil
        invalidateExpirationTimer()
        releaseAssertionIfNeeded()
    }

    private func acquireIfNeeded() {
        guard assertionID == nil else { return }
        do {
            assertionID = try controller.createNoIdleSleepAssertion(reason: reason)
        } catch {
            logError(error)
        }
    }

    private func scheduleExpiration(until expiresAt: Date?) {
        invalidateExpirationTimer()
        guard let expiresAt else { return }

        let interval = expiresAt.timeIntervalSince(now())
        guard interval > 0 else {
            expire()
            return
        }

        expirationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.expire()
            }
        }
    }

    private func expire() {
        let handler = expirationHandler
        expirationHandler = nil
        invalidateExpirationTimer()
        releaseAssertionIfNeeded()
        handler?()
    }

    private func invalidateExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil
    }

    private func releaseAssertionIfNeeded() {
        guard let assertionID else { return }
        controller.releaseAssertion(assertionID)
        self.assertionID = nil
    }
}

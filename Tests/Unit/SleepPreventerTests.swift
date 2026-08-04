import IOKit
import XCTest

@testable import TrayPulsy

@MainActor
final class SleepPreventerTests: XCTestCase {
    func testApplyEnabledAcquiresAssertionAndDisableReleasesIt() {
        let controller = FakePowerAssertionController()
        let preventer = SleepPreventer(
            controller: controller,
            reason: "test keep awake",
            now: { Date(timeIntervalSince1970: 1_000) },
            logError: { _ in }
        )
        var expired = false

        preventer.apply(enabled: true, expiresAt: nil) {
            expired = true
        }

        XCTAssertTrue(preventer.isActive)
        XCTAssertEqual(controller.createdReasons, ["test keep awake"])

        preventer.apply(enabled: false, expiresAt: nil) {
            expired = true
        }

        XCTAssertFalse(preventer.isActive)
        XCTAssertEqual(controller.releasedAssertionIDs, [42])
        XCTAssertFalse(expired)
    }

    func testApplyEnabledDoesNotCreateDuplicateAssertionWhenAlreadyActive() {
        let controller = FakePowerAssertionController()
        let preventer = SleepPreventer(
            controller: controller,
            now: { Date(timeIntervalSince1970: 1_000) },
            logError: { _ in }
        )

        preventer.apply(enabled: true, expiresAt: nil) {}
        preventer.apply(enabled: true, expiresAt: nil) {}

        XCTAssertTrue(preventer.isActive)
        XCTAssertEqual(controller.createdReasons.count, 1)
    }

    func testPastExpirationExpiresWithoutCreatingAssertion() {
        let controller = FakePowerAssertionController()
        let preventer = SleepPreventer(
            controller: controller,
            now: { Date(timeIntervalSince1970: 1_000) },
            logError: { _ in }
        )
        var expired = false

        preventer.apply(enabled: true, expiresAt: Date(timeIntervalSince1970: 999)) {
            expired = true
        }

        XCTAssertTrue(expired)
        XCTAssertFalse(preventer.isActive)
        XCTAssertTrue(controller.createdReasons.isEmpty)
    }

    func testSuspendReleasesAssertionWithoutFiringExpiration() {
        let controller = FakePowerAssertionController()
        let preventer = SleepPreventer(
            controller: controller,
            now: { Date(timeIntervalSince1970: 1_000) },
            logError: { _ in }
        )
        var expired = false

        preventer.apply(enabled: true, expiresAt: nil) {
            expired = true
        }
        preventer.suspend()

        XCTAssertFalse(preventer.isActive)
        XCTAssertEqual(controller.releasedAssertionIDs, [42])
        XCTAssertFalse(expired)
    }

    func testCreateFailureLeavesPreventerInactive() {
        let controller = FakePowerAssertionController()
        controller.createError = PowerAssertionError.createFailed(kIOReturnError)
        let preventer = SleepPreventer(
            controller: controller,
            now: { Date(timeIntervalSince1970: 1_000) },
            logError: { _ in }
        )

        preventer.apply(enabled: true, expiresAt: nil) {}

        XCTAssertFalse(preventer.isActive)
        XCTAssertTrue(controller.releasedAssertionIDs.isEmpty)
    }
}

private final class FakePowerAssertionController: PowerAssertionControlling {
    var createdReasons: [String] = []
    var releasedAssertionIDs: [IOPMAssertionID] = []
    var createError: Error?
    private var nextAssertionID = IOPMAssertionID(42)

    func createNoIdleSleepAssertion(reason: String) throws -> IOPMAssertionID {
        if let createError {
            throw createError
        }
        createdReasons.append(reason)
        defer { nextAssertionID += 1 }
        return nextAssertionID
    }

    func releaseAssertion(_ assertionID: IOPMAssertionID) {
        releasedAssertionIDs.append(assertionID)
    }
}

import Defaults
import Foundation
import Testing

@testable import TrayPulsy

// ═══════════════════════════════════════════════════════════════
// MARK: - Update Check Interval Tests
// ═══════════════════════════════════════════════════════════════

@Suite("UpdateCheckInterval")
struct UpdateCheckIntervalTests {

    // -- seconds --

    @Test("daily seconds is 86400")
    func dailySeconds() {
        #expect(UpdateCheckInterval.daily.seconds == 86_400)
    }

    @Test("weekly seconds is 604800")
    func weeklySeconds() {
        #expect(UpdateCheckInterval.weekly.seconds == 604_800)
    }

    @Test("monthly seconds is 2592000")
    func monthlySeconds() {
        #expect(UpdateCheckInterval.monthly.seconds == 2_592_000)
    }

    // -- rawValue --

    @Test("raw values match expected strings")
    func rawValues() {
        #expect(UpdateCheckInterval.daily.rawValue == "daily")
        #expect(UpdateCheckInterval.weekly.rawValue == "weekly")
        #expect(UpdateCheckInterval.monthly.rawValue == "monthly")
    }

    // -- CaseIterable --

    @Test("allCases contains exactly 3 values")
    func allCases() {
        #expect(UpdateCheckInterval.allCases.count == 3)
    }

    // -- from(seconds:) boundaries --

    @Test("from(seconds:) returns daily for 0")
    func fromZero() {
        #expect(UpdateCheckInterval.from(seconds: 0) == .daily)
    }

    @Test("from(seconds:) returns daily for exactly 86400")
    func fromDailyBoundary() {
        #expect(UpdateCheckInterval.from(seconds: 86_400) == .daily)
    }

    @Test("from(seconds:) returns weekly for 86401")
    func fromJustAboveDaily() {
        #expect(UpdateCheckInterval.from(seconds: 86_401) == .weekly)
    }

    @Test("from(seconds:) returns weekly for exactly 604800")
    func fromWeeklyBoundary() {
        #expect(UpdateCheckInterval.from(seconds: 604_800) == .weekly)
    }

    @Test("from(seconds:) returns monthly for 604801")
    func fromJustAboveWeekly() {
        #expect(UpdateCheckInterval.from(seconds: 604_801) == .monthly)
    }

    @Test("from(seconds:) returns monthly for very large values")
    func fromLargeValue() {
        #expect(UpdateCheckInterval.from(seconds: 10_000_000) == .monthly)
    }

    // -- displayName is non-empty for all cases --

    @Test("displayName is non-empty for all intervals")
    func displayNameNotEmpty() {
        for interval in UpdateCheckInterval.allCases {
            #expect(!interval.displayName.isEmpty, "\(interval.rawValue).displayName should not be empty")
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Update Check State Tests
// ═══════════════════════════════════════════════════════════════

@Suite("UpdateCheckState")
struct UpdateCheckStateTests {

    @Test("idle equals idle")
    func idleEquality() {
        #expect(UpdateCheckState.idle == UpdateCheckState.idle)
    }

    @Test("checking equals checking")
    func checkingEquality() {
        #expect(UpdateCheckState.checking == UpdateCheckState.checking)
    }

    @Test("upToDate equals upToDate")
    func upToDateEquality() {
        #expect(UpdateCheckState.upToDate == UpdateCheckState.upToDate)
    }

    @Test("available with same version are equal")
    func availableSameVersion() {
        #expect(UpdateCheckState.available(version: "1.2.0") == .available(version: "1.2.0"))
    }

    @Test("available with different versions are not equal")
    func availableDifferentVersions() {
        #expect(UpdateCheckState.available(version: "1.2.0") != .available(version: "1.3.0"))
    }

    @Test("error with same message are equal")
    func errorSameMessage() {
        #expect(UpdateCheckState.error("timeout") == .error("timeout"))
    }

    @Test("error with different messages are not equal")
    func errorDifferentMessages() {
        #expect(UpdateCheckState.error("timeout") != .error("network"))
    }

    @Test("different cases are not equal")
    func differentCasesNotEqual() {
        #expect(UpdateCheckState.idle != .checking)
        #expect(UpdateCheckState.upToDate != .idle)
        #expect(UpdateCheckState.available(version: "1.0") != .upToDate)
        #expect(UpdateCheckState.error("err") != .checking)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Update L10n Keys Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Update L10n", .serialized)
struct UpdateL10nTests {

    @Test("English update keys resolve to non-empty values")
    func englishUpdateKeys() {
        Defaults[.language] = .en
        L10n.reload()

        #expect(!L10n.updateAutoCheckHeader.isEmpty)
        #expect(!L10n.updateAutoCheckToggle.isEmpty)
        #expect(!L10n.updateAutoCheckFooter.isEmpty)
        #expect(!L10n.updateCheckNow.isEmpty)
        #expect(!L10n.updateChecking.isEmpty)
        #expect(!L10n.updateUpToDate.isEmpty)
        #expect(!L10n.updateNewVersion.isEmpty)
        #expect(!L10n.updateError.isEmpty)
        #expect(!L10n.updateErrorDebug.isEmpty)
        #expect(!L10n.updateErrorTimeout.isEmpty)
        #expect(!L10n.updateIntervalHeader.isEmpty)
        #expect(!L10n.updateIntervalDaily.isEmpty)
        #expect(!L10n.updateIntervalWeekly.isEmpty)
        #expect(!L10n.updateIntervalMonthly.isEmpty)
        #expect(!L10n.updateReleaseNotes.isEmpty)
        #expect(!L10n.updateViewDetails.isEmpty)
    }

    @Test("Chinese update keys resolve to non-empty values")
    func chineseUpdateKeys() {
        Defaults[.language] = .zhHans
        L10n.reload()

        #expect(!L10n.updateAutoCheckHeader.isEmpty)
        #expect(!L10n.updateAutoCheckToggle.isEmpty)
        #expect(!L10n.updateCheckNow.isEmpty)
        #expect(!L10n.updateChecking.isEmpty)
        #expect(!L10n.updateUpToDate.isEmpty)
        #expect(!L10n.updateNewVersion.isEmpty)
        #expect(!L10n.updateReleaseNotes.isEmpty)
        #expect(!L10n.updateViewDetails.isEmpty)
    }

    @Test("English and Chinese update keys are different")
    func enZhUpdateKeyDiffer() {
        Defaults[.language] = .en
        L10n.reload()
        let enCheckNow = L10n.updateCheckNow

        Defaults[.language] = .zhHans
        L10n.reload()
        let zhCheckNow = L10n.updateCheckNow

        #expect(enCheckNow != zhCheckNow, "EN and ZH updateCheckNow should differ")
    }
}

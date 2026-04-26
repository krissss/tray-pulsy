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
// MARK: - AppUpdateManager Tests (debug builds)
// ═══════════════════════════════════════════════════════════════

@Suite("AppUpdateManager")
@MainActor
struct AppUpdateManagerTests {

    @Test("automaticallyChecksForUpdates returns false in debug builds")
    func autoCheckDebugDefault() {
        let manager = AppUpdateManager()
        #if DEBUG
        #expect(manager.automaticallyChecksForUpdates == false)
        #endif
    }

    @Test("updateCheckInterval defaults to weekly in debug builds")
    func intervalDebugDefault() {
        let manager = AppUpdateManager()
        #if DEBUG
        #expect(manager.updateCheckInterval == 604_800)
        #endif
    }

    @Test("automaticallyDownloadsUpdates returns false in debug builds")
    func autoDownloadDebugDefault() {
        let manager = AppUpdateManager()
        #if DEBUG
        #expect(manager.automaticallyDownloadsUpdates == false)
        #endif
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
        #expect(!L10n.updateCheckNow.isEmpty)
        #expect(!L10n.updateErrorDebug.isEmpty)
        #expect(!L10n.updateIntervalHeader.isEmpty)
        #expect(!L10n.updateIntervalDaily.isEmpty)
        #expect(!L10n.updateIntervalWeekly.isEmpty)
        #expect(!L10n.updateIntervalMonthly.isEmpty)
        #expect(!L10n.updateAutoDownloadToggle.isEmpty)
        #expect(!L10n.updateLastChecked.isEmpty)
    }

    @Test("Chinese update keys resolve to non-empty values")
    func chineseUpdateKeys() {
        Defaults[.language] = .zhHans
        L10n.reload()

        #expect(!L10n.updateAutoCheckHeader.isEmpty)
        #expect(!L10n.updateAutoCheckToggle.isEmpty)
        #expect(!L10n.updateCheckNow.isEmpty)
        #expect(!L10n.updateAutoDownloadToggle.isEmpty)
        #expect(!L10n.updateLastChecked.isEmpty)
    }

    @Test("English update keys resolve to English text")
    func enUpdateKeysMatchEnglish() {
        Defaults[.language] = .en
        L10n.reload()
        #expect(L10n.updateCheckNow == "Check for Updates")
        #expect(L10n.updateAutoDownloadToggle == "Automatically download updates")
    }

    @Test("Chinese update keys resolve to Chinese text")
    func zhUpdateKeysMatchChinese() {
        Defaults[.language] = .zhHans
        L10n.reload()
        #expect(L10n.updateCheckNow == "检查更新")
        #expect(L10n.updateAutoDownloadToggle == "自动下载更新")
    }
}

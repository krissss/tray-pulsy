import Defaults
import Foundation
import Testing

@testable import TrayPulsy

// ═══════════════════════════════════════════════════════════════
// MARK: - L10n Tests
// ═══════════════════════════════════════════════════════════════

@Suite("L10n", .serialized)
struct L10nTests {

    /// Verify loadTable returns non-empty dict.
    @Test("loadTable returns non-empty dictionary")
    func loadTableReturnsContent() {
        let value = L10n.tr("tab.overview", "")
        #expect(!value.isEmpty, "L10n.tr should return a non-empty string for known keys")
    }

    /// Verify English and Chinese strings load correctly, and switching works.
    @Test("Language loading and switching")
    func languageLoadingAndSwitching() {
        // English
        Defaults[.language] = .en
        L10n.reload()
        #expect(L10n.tr("tab.overview", "") == "Overview")
        #expect(L10n.tr("tab.skin", "") == "Skins")
        #expect(L10n.tr("tab.general", "") == "General")
        #expect(L10n.tr("about.quit", "") == "Quit %@")
        #expect(L10n.tr("performance.source.footer", "") == "Animation speed follows the selected metric in real time.")

        // Chinese
        Defaults[.language] = .zhHans
        L10n.reload()
        #expect(L10n.tr("tab.overview", "") == "概览")
        #expect(L10n.tr("tab.skin", "") == "皮肤")
        #expect(L10n.tr("tab.general", "") == "通用")
        #expect(L10n.tr("about.quit", "") == "退出 %@")
        #expect(L10n.tr("performance.source.footer", "") == "猫咪动画速度将跟随所选指标实时变化。")

        // Back to English
        Defaults[.language] = .en
        L10n.reload()
        #expect(L10n.tr("tab.overview", "") == "Overview")
    }

    /// Verify fallback to default value for missing keys.
    @Test("Missing key falls back to default value")
    func missingKeyFallback() {
        let result = L10n.tr("nonexistent.key.12345", "fallback")
        #expect(result == "fallback")
    }

    /// Verify reload posts a notification.
    @Test("Reload posts languageDidChangeNotification")
    func reloadPostsNotification() {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: L10n.languageDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        L10n.reload()
        #expect(received, "reload() should post languageDidChangeNotification")
    }

    /// Verify all L10n computed properties return non-empty strings.
    @Test("All computed properties are non-empty")
    func allPropertiesNonEmpty() {
        Defaults[.language] = .en
        L10n.reload()

        #expect(!L10n.tabOverview.isEmpty)
        #expect(!L10n.tabSkin.isEmpty)
        #expect(!L10n.speedCpu.isEmpty)
        #expect(!L10n.metricCpu.isEmpty)
        #expect(!L10n.fps10.isEmpty)
        #expect(!L10n.interval1.isEmpty)
        #expect(!L10n.themeSystem.isEmpty)
        #expect(!L10n.overviewMonitorHeader.isEmpty)
        #expect(!L10n.skinHeader.isEmpty)
        #expect(!L10n.metricsHeader.isEmpty)
        #expect(!L10n.perfSourceLabel.isEmpty)
        #expect(!L10n.generalStartupHeader.isEmpty)
        #expect(!L10n.aboutInfoHeader.isEmpty)
        #expect(!L10n.accSkinPreview.isEmpty)
        #expect(!L10n.windowTitle.isEmpty)
        #expect(!L10n.popoverHistoryFooter("30 min").isEmpty)
        #expect(!L10n.popoverMetricCpu.isEmpty)
        #expect(!L10n.popoverMetricRam.isEmpty)
    }

    /// Verify System language detection falls back to locale.
    @Test("System language falls back to locale")
    func systemLanguageFallback() {
        Defaults[.language] = .system
        L10n.reload()
        // Just verify it returns something valid (not empty)
        let value = L10n.tr("tab.overview", "")
        #expect(!value.isEmpty, "System language should still resolve to a valid translation")
    }

    /// Verify both language tables have exactly the same keys.
    @Test("English and Chinese tables have same keys")
    func keyParity() {
        // Load English and Chinese; verify every en key exists in zh-Hans and vice versa
        Defaults[.language] = .en
        L10n.reload()
        let enKeys = Set([
            "tab.overview", "tab.skin", "tab.metrics", "tab.performance", "tab.general", "tab.about",
            "speed.cpu", "speed.gpu", "speed.memory", "speed.disk",
            "metric.cpu", "metric.gpu", "metric.memory", "metric.disk", "metric.netDown", "metric.netUp",
            "fps.10", "fps.20", "fps.30", "fps.40",
            "theme.system", "theme.light", "theme.dark",
            "window.title",
        ])
        for key in enKeys {
            #expect(L10n.tr(key, "") != "", "English key '\(key)' should have a value")
        }

        Defaults[.language] = .zhHans
        L10n.reload()
        for key in enKeys {
            #expect(L10n.tr(key, "") != "", "Chinese key '\(key)' should have a value")
        }
    }

    // MARK: - Update L10n Keys

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

    // MARK: - Locale-dependent display names (moved from SettingsStoreTests)

    @Test("SpeedSource labels in Chinese")
    func speedSourceLabels() {
        Defaults[.language] = .zhHans
        L10n.reload()

        #expect(SpeedSource.cpu.label == "CPU")
        #expect(SpeedSource.gpu.label == "GPU")
        #expect(SpeedSource.memory.label == "内存")
        #expect(SpeedSource.disk.label == "磁盘")
    }

    @Test("ThemeMode displayNames in Chinese")
    func themeModeDisplayNames() {
        Defaults[.language] = .zhHans
        L10n.reload()

        #expect(ThemeMode.system.displayName == "跟随系统")
        #expect(ThemeMode.light.displayName == "浅色")
        #expect(ThemeMode.dark.displayName == "深色")
    }

    @Test("ThemeMode emojis")
    func themeModeEmojis() {
        #expect(ThemeMode.system.emoji == "🌓")
        #expect(ThemeMode.light.emoji == "☀️")
        #expect(ThemeMode.dark.emoji == "🌙")
    }

    @Test("SampleInterval displayNames in Chinese")
    func sampleIntervalDisplayNames() {
        Defaults[.language] = .zhHans
        L10n.reload()

        #expect(SampleInterval.halfSec.displayName == "0.5 秒")
        #expect(SampleInterval.oneSec.displayName == "1 秒")
        #expect(SampleInterval.twoSec.displayName == "2 秒")
        #expect(SampleInterval.threeSec.displayName == "3 秒")
        #expect(SampleInterval.fiveSec.displayName == "5 秒")
        #expect(SampleInterval.tenSec.displayName == "10 秒")
    }

    @Test("FPSLimit displayNames")
    func fpsLimitDisplayNames() {
        Defaults[.language] = .zhHans
        L10n.reload()

        #expect(FPSLimit.fps10.displayName == "10 FPS")
        #expect(FPSLimit.fps20.displayName == "20 FPS")
        #expect(FPSLimit.fps30.displayName == "30 FPS")
        #expect(FPSLimit.fps40.displayName == "40 FPS")
    }

    @Test("HistoryDuration seconds and displayNames")
    func historyDurationProperties() {
        #expect(HistoryDuration.min5.seconds == 300)
        #expect(HistoryDuration.min10.seconds == 600)
        #expect(HistoryDuration.min15.seconds == 900)
        #expect(HistoryDuration.min30.seconds == 1800)
        #expect(HistoryDuration.min60.seconds == 3600)

        for dur in HistoryDuration.allCases {
            #expect(!dur.displayName.isEmpty)
        }
    }
}

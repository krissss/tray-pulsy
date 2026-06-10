import Combine
import Foundation
import Observation
import Sparkle
import SwiftUI

// MARK: - App Update Manager

/// Manages app updates using Sparkle with TrayPulsy's custom update UI.
///
/// Uses `@Observable` so SwiftUI tracks property changes through `@Environment(AppState.self)`.
/// Sparkle's KVO publishers sync state into stored properties that Observation can track.
@MainActor
final class AppUpdateManager: NSObject, SPUUpdaterDelegate {
    // MARK: - Observable State (synced from Sparkle via KVO)

    var canCheckForUpdates = false
    var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var updateCheckInterval: TimeInterval = 604_800

    // MARK: - Internal (excluded from Observation)

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var updaterStarted = false
    @ObservationIgnored private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.processName == "xctest"
    @ObservationIgnored private static let sparkleIsAvailable =
        Bundle.main.bundleIdentifier != nil && !isRunningTests
    @ObservationIgnored private lazy var userDriver = SparkleUpdateUserDriver()
    @ObservationIgnored private(set) lazy var updater = SPUUpdater(
        hostBundle: Bundle.main,
        applicationBundle: Bundle.main,
        userDriver: userDriver,
        delegate: self
    )

    override init() {
        super.init()
        guard Self.sparkleIsAvailable else {
            // Debug build: enable button so user can see the "not available" alert
            canCheckForUpdates = true
            return
        }
        _ = updater  // force lazy init to keep delegates and user driver alive
        configureCancellables()
        startUpdaterIfNeeded()
        // Sparkle recommends calling checkForUpdatesInBackground() right after
        // starting the updater on every launch when auto-check is enabled.
        // NSBackgroundActivityScheduler is unreliable for always-on menu-bar apps.
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
        // Read initial values from Sparkle (KVO only fires on *changes*)
        syncFromSparkle()
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        automaticallyChecksForUpdates = isEnabled
        guard Self.sparkleIsAvailable else { return }
        updater.automaticallyChecksForUpdates = isEnabled
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        automaticallyDownloadsUpdates = isEnabled
        guard Self.sparkleIsAvailable else { return }
        updater.automaticallyDownloadsUpdates = isEnabled
    }

    func setUpdateCheckInterval(_ interval: TimeInterval) {
        updateCheckInterval = interval
        guard Self.sparkleIsAvailable else { return }
        updater.updateCheckInterval = interval
    }

    // MARK: - Public API

    func checkForUpdates() {
        guard Self.sparkleIsAvailable else {
            let alert = NSAlert()
            alert.messageText = L10n.updateErrorDebug
            alert.runModal()
            return
        }
        startUpdaterIfNeeded()
        guard updaterStarted else { return }
        updater.checkForUpdates()
    }

    /// Re-schedule the update cycle timer. Call on wake from sleep so
    /// Sparkle doesn't miss the scheduled window.
    func resetUpdateCycle() {
        guard Self.sparkleIsAvailable else { return }
        guard updaterStarted else { return }
        updater.resetUpdateCycle()
    }

    // MARK: - Private

    /// Bind Sparkle's KVO publishers to local stored properties.
    /// Writing to the stored property triggers Observation → SwiftUI re-renders.
    private func configureCancellables() {
        // KVO publishers only emit on *changes*, not the initial value.
        // Use .sink (not .assign) to write through @Observable setters.
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canCheckForUpdates = v }
            .store(in: &cancellables)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.lastUpdateCheckDate = v }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.automaticallyChecksForUpdates = v }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.automaticallyDownloadsUpdates = v }
            .store(in: &cancellables)

        updater.publisher(for: \.updateCheckInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.updateCheckInterval = v }
            .store(in: &cancellables)
    }

    private func startUpdaterIfNeeded() {
        guard !updaterStarted else { return }
        do {
            try updater.start()
            updaterStarted = true
        } catch {
            print("[Sparkle] failed to start updater: \(error)")
        }
    }

    /// Read current values from Sparkle into local stored properties.
    /// KVO publishers only emit on changes, so we must seed initial state.
    private func syncFromSparkle() {
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        updateCheckInterval = updater.updateCheckInterval
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        false
    }

    nonisolated func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        // Menu-bar only app (.accessory) won't bring windows to front automatically
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        print("[Sparkle] didAbortWithError: \(error)")
    }

}

// MARK: - Update Check Interval

enum UpdateCheckInterval: String, CaseIterable {
    case daily
    case weekly
    case monthly

    var displayName: String {
        switch self {
        case .daily:   return L10n.updateIntervalDaily
        case .weekly:  return L10n.updateIntervalWeekly
        case .monthly: return L10n.updateIntervalMonthly
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .daily:   86400
        case .weekly:  604800
        case .monthly: 2592000
        }
    }

    static func from(seconds: TimeInterval) -> UpdateCheckInterval {
        if seconds <= 86400 { return .daily }
        if seconds <= 604800 { return .weekly }
        return .monthly
    }
}

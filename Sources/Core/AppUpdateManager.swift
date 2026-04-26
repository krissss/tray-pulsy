import Combine
import Observation
import Sparkle
import SwiftUI

// MARK: - App Update Manager

/// Manages app updates using Sparkle's standard UI.
/// Uses `SPUStandardUpdaterController` so Sparkle handles update dialogs natively.
///
/// Uses `@Observable` so SwiftUI tracks property changes through `@Environment(AppState.self)`.
/// Sparkle's KVO publishers sync state into stored properties that Observation can track.
@MainActor
final class AppUpdateManager: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    // MARK: - Observable State (synced from Sparkle via KVO)

    var canCheckForUpdates = false
    var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var updateCheckInterval: TimeInterval = 604_800

    // MARK: - Internal (excluded from Observation)

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var updaterStarted = false
    @ObservationIgnored private static let bundleHasIdentifier = Bundle.main.bundleIdentifier != nil
    @ObservationIgnored private(set) lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    var updater: SPUUpdater { updaterController.updater }

    override init() {
        super.init()
        guard Self.bundleHasIdentifier else {
            // Debug build: enable button so user can see the "not available" alert
            canCheckForUpdates = true
            return
        }
        _ = updaterController  // force lazy init to register delegates
        configureCancellables()
        startUpdaterIfNeeded()
        // Read initial values from Sparkle (KVO only fires on *changes*)
        syncFromSparkle()
    }

    // MARK: - Public API

    func checkForUpdates() {
        guard Self.bundleHasIdentifier else {
            let alert = NSAlert()
            alert.messageText = L10n.updateErrorDebug
            alert.runModal()
            return
        }
        startUpdaterIfNeeded()
        updater.checkForUpdates()
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
        guard !updaterStarted, Self.bundleHasIdentifier else { return }
        updaterStarted = true
        updaterController.startUpdater()
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

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { false }

    nonisolated func standardUserDriverWillShowModalAlert() {
        // Menu-bar only app (.accessory) won't bring windows to front automatically
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
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

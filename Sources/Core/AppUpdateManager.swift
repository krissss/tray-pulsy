import Sparkle
import SwiftUI

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case error(String)
}

// MARK: - Silent Update Driver

/// Suppresses all native Sparkle dialogs. Update state is surfaced only
/// through the custom UI in GeneralDetail.
@MainActor
final class SilentUpdateDriver: NSObject, SPUUserDriver {
    private let onStateChange: @Sendable (UpdateCheckState) -> Void
    private let onReleaseNotes: @Sendable (String?) -> Void

    init(
        onStateChange: @escaping @Sendable (UpdateCheckState) -> Void,
        onReleaseNotes: @escaping @Sendable (String?) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onReleaseNotes = onReleaseNotes
        super.init()
    }

    // -- Required --

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        // Auto-accept: user controls this via the settings toggle
        reply(.init(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // Our own UI already shows "Checking…"
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        onStateChange(.available(version: appcastItem.displayVersionString))
        onReleaseNotes(appcastItem.itemDescription)
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        onStateChange(.upToDate)
        acknowledgement()
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        onStateChange(.error(error.localizedDescription))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {}
}

// MARK: - App Update Manager

@MainActor
final class AppUpdateManager: NSObject, ObservableObject {
    private var updater: SPUUpdater!
    private var started = false

    @Published private(set) var checkState: UpdateCheckState = .idle
    @Published private(set) var autoCheckEnabled: Bool = false
    @Published private(set) var releaseNotes: String?
    private var clearTimer: Timer?

    override init() {
        super.init()

        let driver = SilentUpdateDriver(
            onStateChange: { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.checkState = state
                    switch state {
                    case .upToDate, .error:
                        self.scheduleClear()
                    default:
                        self.cancelClear()
                    }
                }
            },
            onReleaseNotes: { [weak self] notes in
                MainActor.assumeIsolated {
                    self?.releaseNotes = notes
                }
            }
        )

        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: nil
        )

        autoCheckEnabled = updater.automaticallyChecksForUpdates

        startUpdater()
    }

    func checkForUpdates() {
        cancelClear()
        checkState = .checking
        releaseNotes = nil

        startUpdater()
        updater.checkForUpdates()

        // Fallback: if no callback within 30 s, assume timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.checkState == .checking else { return }
            self.checkState = .error(L10n.updateErrorTimeout)
            self.scheduleClear()
        }
    }

    func setAutoCheck(_ enabled: Bool) {
        autoCheckEnabled = enabled
        updater.automaticallyChecksForUpdates = enabled
        if enabled {
            startUpdater()
        }
    }

    func setCheckInterval(_ interval: UpdateCheckInterval) {
        updater.updateCheckInterval = interval.seconds
    }

    func currentInterval() -> UpdateCheckInterval {
        UpdateCheckInterval.from(seconds: updater.updateCheckInterval)
    }

    private func startUpdater() {
        guard !started else { return }
        do {
            try updater.start()
            started = true
        } catch {
            print("⚠️ SPUUpdater.start() failed: \(error)")
            checkState = .error(error.localizedDescription)
            scheduleClear()
        }
    }

    private func scheduleClear() {
        cancelClear()
        clearTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkState = .idle
                self?.releaseNotes = nil
            }
        }
    }

    private func cancelClear() {
        clearTimer?.invalidate()
        clearTimer = nil
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

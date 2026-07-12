import AppKit
import Combine
@preconcurrency import Sparkle

final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = UpdateManager()

    @Published private(set) var availableVersion: String?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    private var hasStarted = false

    override private init() {
        super.init()
        _ = updaterController
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updaterController.startUpdater()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        DispatchQueue.main.async { [weak self] in
            self?.availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        DispatchQueue.main.async { [weak self] in
            self?.availableVersion = nil
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { [weak self] in
            self?.availableVersion = nil
        }
    }

    func installAvailableUpdate() {
        availableVersion = nil
        updaterController.checkForUpdates(nil)
    }

    func remindLater() {
        availableVersion = nil
    }

    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        installAvailableUpdate()
    }
}

@preconcurrency import AppKit
import Sparkle
import VellumCore

@MainActor
final class SparkleUpdateController: NSObject, SPUUpdaterDelegate {
    let userDriver: VellumUpdateUserDriver
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
    private var started = false
    private var preferencesObserver: NSObjectProtocol?

    init(prepareToTerminate: @escaping () -> Bool) {
        userDriver = VellumUpdateUserDriver(prepareToTerminate: prepareToTerminate)
        super.init()
        userDriver.checkAgain = { [weak self] in self?.checkForUpdates() }
    }

    @discardableResult
    func start() -> Error? {
        guard !started else { return nil }
        do {
            try updater.start()
            started = true
            synchronizePreferences()
            preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.synchronizePreferences() }
            }
            if updater.automaticallyChecksForUpdates { updater.checkForUpdatesInBackground() }
            return nil
        } catch {
            return error
        }
    }

    func checkForUpdates() {
        if let error = start() { userDriver.presentError(error); return }
        if updater.canCheckForUpdates { updater.checkForUpdates() }
        else { userDriver.showUpdateInFocus() }
    }

    private func synchronizePreferences() {
        let enabled = AppPreferences.automaticallyChecksForUpdates()
        if updater.automaticallyChecksForUpdates != enabled { updater.automaticallyChecksForUpdates = enabled }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if updateCheck == .updatesInBackground { userDriver.beginAutomaticCheck() }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        userDriver.noteBackgroundStage(.downloading, item: item)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        userDriver.noteBackgroundStage(.extracting, item: item)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        userDriver.showAutomaticUpdateReady(item, install: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if updateCheck == .updatesInBackground { userDriver.finishAutomaticCycle(error: error) }
    }

    deinit {
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
    }
}

@MainActor
final class VellumUpdateUserDriver: NSObject, SPUUserDriver {
    let windowController: UpdateWindowController
    private(set) var content: UpdateWindowContent
    var checkAgain: (() -> Void)?
    private let prepareToTerminate: () -> Bool
    private let openURL: (URL) -> Void
    private var generation = 0
    private var receivedBytes: UInt64 = 0
    private var expectedBytes: UInt64 = 0
    private var releaseURL = URL(string: "https://github.com/AbyssSkb/Vellum/releases/latest")!
    private var language: AppUILanguage { .saved() }

    init(currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
         windowController: UpdateWindowController = UpdateWindowController(),
         prepareToTerminate: @escaping () -> Bool = { true },
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.windowController = windowController
        self.prepareToTerminate = prepareToTerminate
        self.openURL = openURL
        content = UpdateWindowContent(phase: .checking, currentVersion: currentVersion)
        super.init()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: AppPreferences.automaticallyChecksForUpdates(), sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        content = UpdateWindowContent(phase: .checking, currentVersion: content.currentVersion)
        present(actions: [action(.cancel, key: "c") { [weak self] in self?.dismiss(); cancellation() }], close: { [weak self] in self?.dismiss(); cancellation() })
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        offer(appcastItem, stage: state.stage, reply: reply)
    }

    func offer(_ item: SUAppcastItem, stage: SPUUserUpdateStage, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        setItem(item)
        content.phase = stage == .notDownloaded ? .available : .ready
        let close = { [weak self] in self?.dismiss(); reply(.dismiss) }
        var actions = [action(.later, key: "l", handler: close), releaseAction()]
        if !item.isInformationOnlyUpdate {
            actions.append(action(stage == .notDownloaded ? .downloadUpdate : .restartAndUpdate,
                                  key: stage == .notDownloaded ? "u" : "r", primary: true) { [weak self] in
                guard let self, stage != .installing || self.prepareToTerminate() else { return }
                self.invalidateActions()
                reply(.install)
            })
        }
        present(actions: actions, close: close)
    }

    func showAutomaticUpdateReady(_ item: SUAppcastItem, install: @escaping () -> Void) {
        setItem(item)
        content.phase = .ready
        present(actions: [action(.later, key: "l") { [weak self] in self?.windowController.dismiss() }, releaseAction(),
                          action(.restartAndUpdate, key: "r", primary: true) { [weak self] in
            guard let self, self.prepareToTerminate() else { return }
            self.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: install)
            install()
        }], close: { [weak self] in self?.windowController.dismiss() }, activate: false)
    }

    func noteBackgroundStage(_ phase: UpdateWindowContent.Phase, item: SUAppcastItem) {
        invalidateActions()
        content.actions = []
        setItem(item)
        content.phase = phase
        if windowController.window?.isVisible == true { showUpdateInFocus() }
    }

    func beginAutomaticCheck() {
        invalidateActions()
        content = UpdateWindowContent(phase: .checking, currentVersion: content.currentVersion)
        if windowController.window?.isVisible == true { showUpdateInFocus() }
    }

    func finishAutomaticCycle(error: Error?) {
        let wasVisible = windowController.window?.isVisible == true
        dismiss()
        content.actions = []
        guard wasVisible, let error else { return }
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain, nsError.code == Int(SUError.noUpdateError.rawValue) {
            showUpdateNotFoundWithError(error, acknowledgement: {})
        } else {
            presentError(error)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if let text = String(data: downloadData.data, encoding: .utf8) {
            content.releaseNotes = Self.releaseNotes(text)
            windowController.update(content)
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // The release-page action remains available when linked notes cannot be fetched.
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        content = UpdateWindowContent(phase: .upToDate, currentVersion: content.currentVersion)
        present(actions: [action(.closeUpdate, key: "c", primary: true) { [weak self] in self?.dismiss(); acknowledgement() }],
                close: { [weak self] in self?.dismiss(); acknowledgement() })
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        presentError(error, acknowledgement: acknowledgement)
    }

    func presentError(_ error: Error, acknowledgement: @escaping () -> Void = {}) {
        content.phase = .error
        content.message = error.localizedDescription
        let close = { [weak self] in self?.dismiss(); acknowledgement() }
        present(actions: [action(.closeUpdate, key: "c", handler: close), releaseAction(),
                          action(.retryUpdate, key: "r", primary: true) { [weak self] in
            self?.dismiss(); acknowledgement()
            DispatchQueue.main.async { [weak self] in self?.checkAgain?() }
        }], close: close)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        receivedBytes = 0
        expectedBytes = 0
        content.phase = .downloading
        content.message = nil
        content.progress = nil
        let close = { [weak self] in self?.dismiss(); cancellation() }
        present(actions: [action(.cancel, key: "c", handler: close)], close: close)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        updateDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        updateDownloadProgress()
    }

    private func updateDownloadProgress() {
        content.progress = expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil
        let received = ByteCountFormatter.string(fromByteCount: Int64(clamping: receivedBytes), countStyle: .file)
        content.message = expectedBytes > 0 ? "\(received) / \(ByteCountFormatter.string(fromByteCount: Int64(clamping: expectedBytes), countStyle: .file))" : language.text(.downloadedBytes(received))
        windowController.update(content)
    }

    func showDownloadDidStartExtractingUpdate() {
        content.phase = .extracting
        content.message = nil
        content.progress = nil
        present(actions: [], close: {})
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        content.progress = max(0, min(1, progress))
        windowController.update(content)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        content.phase = .ready
        content.message = nil
        content.progress = nil
        let close = { [weak self] in self?.dismiss(); reply(.dismiss) }
        present(actions: [action(.later, key: "l", handler: close), releaseAction(),
                          action(.restartAndUpdate, key: "r", primary: true) { [weak self] in
            guard let self, self.prepareToTerminate() else { return }
            self.invalidateActions()
            reply(.install)
        }], close: close)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        content.phase = .installing
        content.message = nil
        content.progress = nil
        let actions = applicationTerminated ? [] : [action(.restartAndUpdate, key: "r", primary: true) { [weak self] in
            guard self?.prepareToTerminate() == true else { return }
            retryTerminatingApplication()
        }]
        present(actions: actions, close: {})
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        dismiss()
        acknowledgement()
    }

    func dismissUpdateInstallation() { dismiss() }

    func showUpdateInFocus() {
        if content.actions.isEmpty && [.checking, .downloading, .extracting].contains(content.phase) {
            present(actions: [action(.closeUpdate, key: "c") { [weak self] in self?.windowController.dismiss() }],
                    close: { [weak self] in self?.windowController.dismiss() })
        } else { windowController.present(content) }
    }

    private func setItem(_ item: SUAppcastItem) {
        content.updateVersion = item.displayVersionString
        content.releaseNotes = Self.releaseNotes(item.itemDescription)
        content.message = nil
        content.progress = nil
        releaseURL = item.infoURL ?? URL(string: "https://github.com/AbyssSkb/Vellum/releases/tag/v\(item.displayVersionString)") ?? releaseURL
    }

    static func releaseNotes(_ text: String?) -> [AppReleaseNotesSection] {
        AppReleaseNotesParser.sections(from: text, maxPlainNotes: .max, maxNotesPerVersion: .max)
    }

    private func releaseAction() -> UpdateWindowAction {
        action(.openGitHub, key: "o") { [weak self] in guard let self else { return }; self.openURL(self.releaseURL) }
    }

    private func action(_ title: AppText, key: String, primary: Bool = false, handler: @escaping () -> Void) -> UpdateWindowAction {
        UpdateWindowAction(title: language.text(title), key: key, isPrimary: primary, handler: handler)
    }

    private func present(actions: [UpdateWindowAction], close: @escaping () -> Void, activate: Bool = true) {
        generation += 1
        let token = generation
        content.actions = actions.map { original in
            var action = original
            action.handler = { [weak self] in guard self?.generation == token else { return }; original.handler() }
            return action
        }
        windowController.onClose = { [weak self] in guard self?.generation == token else { return }; close() }
        windowController.present(content, activate: activate)
    }

    private func invalidateActions() { generation += 1 }

    private func dismiss() { invalidateActions(); windowController.dismiss() }
}

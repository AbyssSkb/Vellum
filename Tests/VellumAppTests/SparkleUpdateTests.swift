import AppKit
import Sparkle
import Testing
import VellumCore
@testable import Vellum

@Suite(.serialized)
@MainActor
struct SparkleUpdateTests {
    @Test
    func upToDateResultAcknowledgesImmediatelyAndDismissesTheCheckWindow() {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        var cancellations = 0
        driver.showUserInitiatedUpdateCheck { cancellations += 1 }
        let cancel = driver.content.actions[0].handler
        var acknowledgements = 0
        driver.showUpdateNotFoundWithError(URLError(.unknown)) { acknowledgements += 1 }
        cancel()
        #expect(cancellations == 0)
        #expect(driver.content.phase == .upToDate)
        #expect(driver.content.actions.isEmpty)
        #expect(driver.windowController.window?.isVisible == false)
        driver.dismissUpdateInstallation()
        driver.windowController.onClose?()
        driver.showUpdateInFocus()
        #expect(driver.windowController.window?.isVisible == false)
        #expect(acknowledgements == 1)
    }

    @Test(arguments: ["r", "R"])
    func retryAcknowledgesTheFailedCycleBeforeRequestingANewCheck(key: String) throws {
        let driver = makeDriver()
        let owner = makeOwnerWindow()
        driver.captureNotificationWindow(owner)
        defer { owner.close(); driver.windowController.dismiss() }
        var callbacks: [String] = []
        driver.checkAgain = { callbacks.append("retry") }
        driver.showUpdaterError(URLError(.cannotConnectToHost)) { callbacks.append("acknowledge") }
        #expect(callbacks == ["acknowledge"])
        #expect(driver.windowController.window?.isVisible == false)
        driver.dismissUpdateInstallation()
        driver.finishAutomaticCycle(error: URLError(.cannotConnectToHost))
        let retry = try #require(driver.content.actions.last?.handler)
        let details = try #require(detailsButton(in: owner))
        details.performClick(nil)
        #expect(driver.windowController.window?.isVisible == true)
        let window = try #require(driver.windowController.window)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: key == "R" ? .shift : [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 15))
        window.sendEvent(event)
        #expect(callbacks == ["acknowledge", "retry"])
        #expect(window.isVisible == false)
        retry()
        #expect(callbacks == ["acknowledge", "retry"])
    }

    @Test(arguments: AppUILanguage.allCases)
    func updateErrorsShowTheUnderlyingCauseAndRecoveryDetails(language: AppUILanguage) throws {
        let preference = AppPreferenceKeys.appLanguage
        let previous = UserDefaults.standard.object(forKey: preference)
        UserDefaults.standard.set(language.rawValue, forKey: preference)
        defer { UserDefaults.standard.set(previous, forKey: preference) }
        let cause = NSError(domain: SUSparkleErrorDomain, code: 2001, userInfo: [
            NSLocalizedDescriptionKey: "A network error occurred: service unavailable (503).",
            NSLocalizedFailureReasonErrorKey: "The server is temporarily unavailable.",
            NSLocalizedRecoverySuggestionErrorKey: "Please retry later."
        ])
        let download = NSError(domain: SUSparkleErrorDomain, code: 2001, userInfo: [
            NSLocalizedDescriptionKey: "An error occurred while downloading the update.", NSUnderlyingErrorKey: cause
        ])
        let error = NSError(domain: SUSparkleErrorDomain, code: 2001, userInfo: [
            NSLocalizedDescriptionKey: "An error occurred in retrieving update information.",
            NSLocalizedFailureReasonErrorKey: "  An error occurred in retrieving update information.  ",
            NSLocalizedRecoverySuggestionErrorKey: " \n ", NSUnderlyingErrorKey: download
        ])
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        driver.showUpdaterError(error, acknowledgement: {})
        let message = try #require(driver.content.message)
        #expect(message.hasPrefix(error.localizedDescription))
        #expect(message.contains(download.localizedDescription))
        #expect(message.contains(cause.localizedDescription))
        #expect(message.contains("The server is temporarily unavailable."))
        #expect(message.contains("Please retry later."))
        #expect(message.components(separatedBy: error.localizedDescription).count == 2)
        #expect(message.components(separatedBy: language.text(.updateErrorCode(domain: SUSparkleErrorDomain, code: 2001))).count == 4)
        #expect(!message.contains("\n\n\n"))
        let reason = "The server is temporarily unavailable."
        driver.presentError(NSError(domain: "NetworkFixture", code: 503, userInfo: [NSLocalizedFailureReasonErrorKey: reason]))
        #expect(try #require(driver.content.message).components(separatedBy: reason).count == 2)
    }

    @Test
    func updateErrorsIncludeSwiftUnderlyingErrorsAndStopAtCycles() throws {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        let error = NSError(domain: SUSparkleErrorDomain, code: 2001, userInfo: [NSUnderlyingErrorKey: URLError(.timedOut)])
        driver.presentError(error)
        let message = try #require(driver.content.message)
        #expect(message.contains(URLError(.timedOut).localizedDescription))
        #expect(message.contains("NSURLErrorDomain"))
        #expect(message.contains("-1001"))
        let cyclicError = CyclicUpdateError(domain: "CyclicUpdateError", code: 1)
        driver.presentError(cyclicError)
        let cyclicMessage = try #require(driver.content.message)
        #expect(cyclicMessage.components(separatedBy: cyclicError.localizedDescription).count == 2)
    }

    @Test(arguments: [false, true])
    func terminalResultsKeepTheOriginalWindowAndDoNotRequestUpdateFocus(failed: Bool) throws {
        let driver = makeDriver()
        let owner = makeOwnerWindow()
        driver.captureNotificationWindow(owner)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                             styleMask: .titled, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { owner.close(); other.close(); driver.windowController.dismiss() }
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        #expect(driver.notificationWindow === owner)
        other.makeKeyAndOrderFront(nil)
        let resultWindow = FocusRecordingWindow(contentRect: .zero, styleMask: .titled,
                                               backing: .buffered, defer: false)
        resultWindow.isReleasedWhenClosed = false
        driver.windowController.dismiss()
        driver.windowController.window = resultWindow
        defer { resultWindow.close() }
        let responder = other.firstResponder
        var acknowledgements = 0

        if failed {
            driver.showUpdaterError(URLError(.cannotConnectToHost)) { acknowledgements += 1 }
        } else {
            driver.showUpdateNotFoundWithError(URLError(.unknown)) { acknowledgements += 1 }
        }

        #expect(driver.notificationWindow === owner)
        #expect(resultWindow.keyPresentationCount == 0)
        #expect(other.firstResponder === responder)
        #expect(acknowledgements == 1)
    }

    @Test
    func aNewCheckInvalidatesThePreviousErrorsRetryAction() throws {
        let driver = makeDriver()
        let owner = makeOwnerWindow()
        driver.captureNotificationWindow(owner)
        defer { owner.close(); driver.windowController.dismiss() }
        var retries = 0
        driver.checkAgain = { retries += 1 }
        driver.presentError(URLError(.timedOut))
        let oldRetry = try #require(driver.content.actions.last?.handler)
        let oldDetails = try #require(detailsButton(in: owner))
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        driver.windowController.dismiss()
        oldDetails.performClick(nil)
        oldRetry()
        #expect(retries == 0)
        #expect(driver.content.phase == .checking)
        #expect(driver.windowController.window?.isVisible == false)
    }

    @Test
    func restartWaitsForSuccessfulSaveAndRespondsOnlyOnce() {
        var saved = false
        let driver = makeDriver(prepare: { saved })
        defer { driver.windowController.dismiss() }
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        let restart = driver.content.actions.last!.handler
        restart()
        #expect(choices.isEmpty)
        saved = true
        restart()
        restart()
        #expect(choices == [.install])
    }

    @Test(arguments: [SPUUserUpdateStage.notDownloaded, .downloaded])
    func confirmedUpdateInstallsWhenReadyWithoutASecondPrompt(stage: SPUUserUpdateStage) throws {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        var choices: [SPUUserUpdateChoice] = []
        driver.offer(try item(), stage: stage) { choices.append($0) }
        #expect(driver.content.actions.last?.key == (stage == .notDownloaded ? "u" : "r"))
        driver.content.actions.last?.handler()
        #expect(choices == [.install])
        if stage == .notDownloaded {
            driver.showDownloadInitiated(cancellation: {})
            driver.showDownloadDidReceiveExpectedContentLength(100)
            driver.showDownloadDidReceiveData(ofLength: 40)
            #expect(driver.content.progress == 0.4)
        }
        driver.showDownloadDidStartExtractingUpdate()
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices == [.install, .install])
        #expect(driver.content.phase == .installing)
        #expect(driver.content.actions.isEmpty)
    }

    @Test
    func automaticRestartAfterDownloadWaitsForSuccessfulSave() throws {
        var saved = false
        let driver = makeDriver(prepare: { saved })
        defer { driver.windowController.dismiss() }
        driver.offer(try item(), stage: .notDownloaded, reply: { _ in })
        driver.content.actions.last?.handler()
        driver.showDownloadInitiated(cancellation: {})
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices.isEmpty)
        #expect(driver.content.phase == .ready)
        saved = true
        let restart = try #require(driver.content.actions.last?.handler)
        restart()
        restart()
        #expect(choices == [.install])
    }

    @Test(arguments: [false, true])
    func canceledOrFailedDownloadClearsTheRestartChoice(failed: Bool) throws {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        driver.offer(try item(), stage: .notDownloaded, reply: { _ in })
        driver.content.actions.last?.handler()
        var cancellations = 0
        driver.showDownloadInitiated { cancellations += 1 }
        let cancel = try #require(driver.content.actions.first?.handler)
        if failed {
            driver.showUpdaterError(URLError(.cannotConnectToHost), acknowledgement: {})
            cancel()
            #expect(cancellations == 0)
        } else {
            cancel()
            cancel()
            #expect(cancellations == 1)
        }
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices.isEmpty)
        #expect(driver.content.phase == .ready)
    }

    @Test
    func backgroundReadyCanBeDeferredAndReopenedWithoutLosingTheInstallAction() throws {
        var installed = 0
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        driver.showAutomaticUpdateReady(try item()) { installed += 1 }
        driver.content.actions[0].handler()
        #expect(driver.windowController.window?.isVisible == false)
        #expect(installed == 0)
        driver.showUpdateInFocus()
        #expect(driver.windowController.window?.isVisible == true)
        let restart = driver.content.actions.last!.handler
        restart()
        restart()
        #expect(installed == 1)
    }

    @Test
    func backgroundReadyRequestsKeyFocusAndAcceptsRestartWithoutAClick() throws {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        let eventWindow = try #require(driver.windowController.window)
        let window = FocusRecordingWindow(contentRect: .zero, styleMask: .titled,
                                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        driver.windowController.window = window
        defer { window.close() }
        let wasActive = NSApp.isActive
        var installations = 0

        driver.showAutomaticUpdateReady(try item()) { installations += 1 }
        #expect(window.keyPresentationCount == 1)
        #expect(NSApp.isActive == wasActive)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: eventWindow.windowNumber, context: nil,
            characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
        eventWindow.sendEvent(event)
        #expect(installations == 1)
    }

    @Test
    func aStaleConfirmationCannotInstallAReplacementUpdate() throws {
        var installed: [String] = []
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        driver.showAutomaticUpdateReady(try item("0.8.9")) { installed.append("old") }
        let oldRestart = driver.content.actions.last!.handler
        driver.showAutomaticUpdateReady(try item("0.8.10")) { installed.append("new") }
        oldRestart()
        #expect(installed.isEmpty)
        driver.content.actions.last?.handler()
        #expect(installed == ["new"])
    }

    @Test
    func canceledAutomaticRelaunchKeepsTheRetryActionAndFailuresClearOldCallbacks() throws {
        var attempts = 0
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        driver.showAutomaticUpdateReady(try item()) { attempts += 1 }
        let oldRestart = driver.content.actions.last!.handler
        oldRestart()
        #expect(driver.content.phase == .installing)
        #expect(driver.content.actions.last?.key == "r")
        driver.content.actions.last?.handler()
        #expect(attempts == 2)
        driver.finishAutomaticCycle(error: URLError(.cannotConnectToHost))
        #expect(driver.content.phase == .error)
        oldRestart()
        #expect(attempts == 2)
    }

    @Test
    func focusingABackgroundCheckShowsNoUpdateAsSuccessAndRefreshesProgressActions() throws {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        driver.showUpdateNotFoundWithError(URLError(.unknown), acknowledgement: {})
        driver.beginAutomaticCheck()
        driver.showUpdateInFocus()
        #expect(driver.content.phase == .checking)
        #expect(driver.content.actions.first?.key == "c")
        driver.noteBackgroundStage(.downloading, item: try item())
        driver.showUpdateInFocus()
        #expect(driver.content.phase == .downloading)
        #expect(driver.content.actions.first?.key == "c")
        driver.finishAutomaticCycle(error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        #expect(driver.content.phase == .upToDate)
        #expect(driver.content.actions.isEmpty)
        #expect(driver.windowController.window?.isVisible == false)
    }

    @Test
    func longReleaseNotesAreNotLimitedToTheOldEightLinePreview() {
        let text = (1...80).map { "- Improvement \($0)" }.joined(separator: "\n")
        let sections = VellumUpdateUserDriver.releaseNotes(text)
        #expect(sections.first?.notes.count == 80)
        #expect(sections.first?.notes.last == "Improvement 80")
    }

    @Test
    func sparklesOptionalDelegateCallbacksHaveTheCorrectSelectors() {
        let controller = SparkleUpdateController(prepareToTerminate: { true })
        #expect(controller.responds(to: #selector(SPUUpdaterDelegate.updater(_:mayPerform:))))
        #expect(controller.responds(to: #selector(SPUUpdaterDelegate.updater(_:willDownloadUpdate:with:))))
        #expect(controller.responds(to: #selector(SPUUpdaterDelegate.updater(_:willExtractUpdate:))))
        #expect(controller.responds(to: #selector(SPUUpdaterDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:))))
        #expect(controller.responds(to: #selector(SPUUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:))))
    }

    private func makeDriver(prepare: @escaping () -> Bool = { true }) -> VellumUpdateUserDriver {
        _ = NSApplication.shared
        return VellumUpdateUserDriver(currentVersion: "0.8.8", prepareToTerminate: prepare, openURL: { _ in })
    }

    private func makeOwnerWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func detailsButton(in window: NSWindow) -> NSButton? {
        (window.contentView?.superview ?? window.contentView)?.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
            .first { $0.title == AppUILanguage.saved().text(.updateDetails) }
    }

    private final class FocusRecordingWindow: NSWindow {
        var keyPresentationCount = 0
        override func makeKeyAndOrderFront(_ sender: Any?) { keyPresentationCount += 1 }
        override func orderFront(_ sender: Any?) {}
    }

    private final class CyclicUpdateError: NSError, @unchecked Sendable {
        override var userInfo: [String: Any] { [NSUnderlyingErrorKey: self] }
    }

    private func item(_ version: String = "0.8.9") throws -> SUAppcastItem {
        try #require(SUAppcastItem(dictionary: [
            "enclosure": ["url": "https://example.com/Vellum.dmg", "sparkle:version": version],
            "description": "- Improved reading\n- Refined updates"
        ]))
    }
}

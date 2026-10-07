import AppKit
import Sparkle
import Testing
import VellumCore
@testable import Vellum

@Suite(.serialized)
@MainActor
struct SparkleUpdateTests {
    @Test
    func manualCheckAndResultsUseTheSameWindowAndOnlyAcknowledgeOnce() {
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
        let close = driver.content.actions[0].handler
        close()
        close()
        #expect(acknowledgements == 1)
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

    @Test
    func manualDownloadAndRestartAreDistinctActions() throws {
        let driver = makeDriver()
        defer { driver.windowController.dismiss() }
        var choices: [SPUUserUpdateChoice] = []
        driver.offer(try item(), stage: .notDownloaded) { choices.append($0) }
        #expect(driver.content.phase == .available)
        #expect(driver.content.actions.last?.key == "u")
        driver.content.actions.last?.handler()
        #expect(choices == [.install])
        driver.showDownloadInitiated(cancellation: {})
        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 40)
        #expect(driver.content.progress == 0.4)
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(driver.content.phase == .ready)
        #expect(driver.content.actions.last?.key == "r")
        #expect(choices.count == 1)
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
        driver.content.actions[0].handler()
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
        driver.content.actions[0].handler()
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

    private func item(_ version: String = "0.8.9") throws -> SUAppcastItem {
        try #require(SUAppcastItem(dictionary: [
            "enclosure": ["url": "https://example.com/Vellum.dmg", "sparkle:version": version],
            "description": "- Improved reading\n- Refined updates"
        ]))
    }
}

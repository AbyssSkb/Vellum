@preconcurrency import AppKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Keyboard controller open URLs")
struct KeyboardControllerOpenURLTests {
    @Test(arguments: [true, false])
    func queuedURLsWaitUntilDelegateIsAssigned(queuedBeforeControllerInit: Bool) {
        let relay = OpenURLRelay(currentTime: { 100 })
        let url = URL(fileURLWithPath: "/tmp/queued.pdf").standardizedFileURL
        let delegate = RecordingOpenURLKeyboardDelegate()

        if queuedBeforeControllerInit {
            relay.open([url])
        }
        let controller = KeyboardController(
            installsKeyMonitor: false,
            notificationCenter: NotificationCenter(),
            openURLRelay: relay
        )
        if !queuedBeforeControllerInit {
            relay.open([url])
        }
        controller.delegate = nil
        #expect(delegate.openedBatches.isEmpty)

        controller.delegate = delegate
        #expect(delegate.openedBatches == [[url]])

        let replacementDelegate = RecordingOpenURLKeyboardDelegate()
        controller.delegate = replacementDelegate
        #expect(delegate.openedBatches == [[url]])
        #expect(replacementDelegate.openedBatches.isEmpty)
    }
}

@MainActor
private final class RecordingOpenURLKeyboardDelegate: KeyboardControllerDelegate {
    var activeReaderController: ReaderController? { nil }
    var readerWindow: NSWindow? { nil }
    private(set) var openedBatches: [[URL]] = []

    func handleVimCommand(_ command: VimCommand) {}

    func open(urls: [URL]) {
        openedBatches.append(urls)
    }
}

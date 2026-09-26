@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Keyboard controller")
struct KeyboardControllerTests {
    @Test
    func shortTabPressKeepsToggleOutlineBehavior() {
        let controller = KeyboardController(
            tabPageOverviewDelay: 10,
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))

        #expect(delegate.commands == [.toggleOutline])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func longTabPressBeginsMovesAndFinishesPageOverview() {
        let controller = KeyboardController(
            tabPageOverviewDelay: 0.001,
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "l", keyCode: 37)))
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "l", keyCode: 37)))
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))

        #expect(delegate.commands == [])
        #expect(delegate.reader.actions == [
            .beginPageOverview,
            .movePageOverview(.next),
            .finishPageOverview
        ])
    }

    @Test
    func slashRoutesToSearchCommand() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "/", keyCode: 44)))

        #expect(delegate.commands == [.beginSearch])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func repeatedNSearchKeyRoutesEveryEvent() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "n", keyCode: 45)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "n", keyCode: 45, isRepeat: true)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "N", keyCode: 45, isRepeat: true)))

        #expect(delegate.commands == [.searchNext, .searchNext, .searchPrevious])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func dScrollsWhenOnlySearchTargetExists() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.hasSearchTextTarget = true
        delegate.reader.deleteHighlightsResult = true
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "d", keyCode: 2)))

        #expect(delegate.commands == [.largeScrollDown])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func dDeletesHighlightWhenTextSelectionExists() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.hasNavigableTextSelection = true
        delegate.reader.deleteHighlightsResult = true
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "d", keyCode: 2)))

        #expect(delegate.commands == [])
        #expect(delegate.reader.actions == [.deleteHighlights])
    }

    @Test
    func uppercaseDScrollsEvenWhenTextSelectionExists() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.hasNavigableTextSelection = true
        delegate.reader.deleteHighlightsResult = true
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "D", keyCode: 2)))

        #expect(delegate.commands == [.extraLargeScrollDown])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func uppercaseTRoutesToTabSwitcherCommand() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "T", keyCode: 17)))

        #expect(delegate.commands == [.showTabSwitcher])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func commandShortcutsPassThroughToAppMenus() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: "q", keyCode: 12, modifierFlags: [.command])))

        #expect(delegate.commands == [])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func modifiedKeyReleaseStopsContinuousScrolling() {
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
            let delegate = RecordingKeyboardDelegate()
            controller.delegate = delegate

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
            #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38, modifierFlags: modifier)))
            RunLoop.main.run(until: Date().addingTimeInterval(0.10))
            #expect(delegate.commands == [.scrollDown])

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
            #expect(delegate.commands == [.scrollDown, .scrollDown])
            #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38)))
        }
    }

    @Test
    func modifierShortcutStopsContinuousScrollingWithoutBeingConsumed() {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: "o", keyCode: 31, modifierFlags: [.command])))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == [.scrollDown])
    }

    @Test
    func deactivationClearsScrollingAndPendingTabPress() {
        for name in [NSApplication.willResignActiveNotification, NSWindow.didResignKeyNotification] {
            let controller = KeyboardController(
                tabPageOverviewDelay: 0.001,
                installsKeyMonitor: false,
                installsOpenURLObserver: false
            )
            let delegate = RecordingKeyboardDelegate()
            controller.delegate = delegate

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
            NotificationCenter.default.post(name: name, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.10))
            #expect(delegate.commands == [.scrollDown])

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
            NotificationCenter.default.post(name: name, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))
            #expect(delegate.commands == [.scrollDown])
            #expect(delegate.reader.actions.isEmpty)
        }
    }

    @Test
    func deactivationDismissesActivePageOverview() {
        let controller = KeyboardController(
            tabPageOverviewDelay: 0.001,
            installsKeyMonitor: false,
            installsOpenURLObserver: false
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)
        #expect(delegate.reader.actions == [.beginPageOverview, .finishPageOverview])
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))
    }

    @Test
    func changingFirstResponderStopsContinuousScrolling() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: false)
        let first = NSTextView()
        let second = NSTextView()
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(second)
        #expect(window.makeFirstResponder(first))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        let event = WindowKeyboardEvent()
        event.targetWindow = window
        #expect(controller.handleKeyEvent(event))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        let commandsBeforeFocusChange = delegate.commands
        #expect(window.makeFirstResponder(second))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == commandsBeforeFocusChange)
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38)))
    }

    private func keyEvent(
        _ type: NSEvent.EventType,
        key: String,
        keyCode: UInt16,
        isRepeat: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}

private final class WindowKeyboardEvent: NSEvent {
    var targetWindow: NSWindow?
    override var window: NSWindow? { targetWindow }
    override var type: NSEvent.EventType { .keyDown }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var charactersIgnoringModifiers: String? { "j" }
    override var isARepeat: Bool { false }
}

@MainActor
private final class RecordingKeyboardDelegate: KeyboardControllerDelegate {
    let reader = RecordingKeyboardReaderController()
    private(set) var commands: [VimCommand] = []
    private(set) var openedURLs: [URL] = []

    var activeReaderController: ReaderController? {
        reader
    }

    func handleVimCommand(_ command: VimCommand) {
        commands.append(command)
    }

    func open(urls: [URL]) {
        openedURLs.append(contentsOf: urls)
    }
}

@MainActor
private final class RecordingKeyboardReaderController: ReaderController {
    var isAIInteractionActive = false
    var hasNavigableTextSelection = false
    var hasSearchTextTarget = false
    var isPageOverviewActive = false
    var deleteHighlightsResult = false
    private(set) var actions: [Action] = []

    func snapshot() -> ReaderSnapshot? { nil }

    func focus() {}

    func beginPageOverview() -> Bool {
        actions.append(.beginPageOverview)
        isPageOverviewActive = true
        return true
    }

    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool {
        actions.append(.movePageOverview(navigation))
        return true
    }

    func finishPageOverview() {
        actions.append(.finishPageOverview)
        isPageOverviewActive = false
    }

    func beginSearchCommand() {
        actions.append(.beginSearch)
    }

    func handleAIKeyEvent(_ event: NSEvent) -> Bool { false }

    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool { false }

    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool { false }

    func vimDeleteHighlightsForSelection() -> Bool {
        actions.append(.deleteHighlights)
        return deleteHighlightsResult
    }

    func vimScroll(x: CGFloat, y: CGFloat) {}

    func vimMoveByPage(_ delta: Int) {}

    func vimGoToFirstPage() {}

    func vimGoToLastPage() {}

    func vimGoToPage(_ pageNumber: Int) {}

    func vimGoToDestination(_ destination: PDFDestination) {}

    func vimJumpBack() {}

    func vimJumpForward() {}

    func vimSearchNext() {}

    func vimSearchPrevious() {}

    func vimMaterializeSearchSelection() {}

    func vimCopySelection() {}

    func vimHighlightSelection(color: NSColor) {}

    func vimExplainSelectedHighlight() {}

    func vimStartAIConversation() {}

    func vimZoom(by factor: CGFloat) {}

    func vimZoomToPageFit() {}

    func vimZoomToFit() {}

    enum Action: Equatable {
        case beginPageOverview
        case movePageOverview(PageOverviewNavigation)
        case finishPageOverview
        case beginSearch
        case deleteHighlights
    }
}

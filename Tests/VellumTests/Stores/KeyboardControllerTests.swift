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

    private func keyEvent(
        _ type: NSEvent.EventType,
        key: String,
        keyCode: UInt16,
        isRepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
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
    var isPageOverviewActive = false
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

    func vimDeleteHighlightsForSelection() -> Bool { false }

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

    func vimCopySelection() {}

    func vimHighlightSelection(color: NSColor) {}

    func vimExplainSelectedHighlight() {}

    func vimZoom(by factor: CGFloat) {}

    func vimZoomToPageFit() {}

    func vimZoomToFit() {}

    enum Action: Equatable {
        case beginPageOverview
        case movePageOverview(PageOverviewNavigation)
        case finishPageOverview
        case beginSearch
    }
}

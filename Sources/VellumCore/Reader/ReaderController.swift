@preconcurrency import AppKit
import PDFKit

@MainActor
protocol ReaderController: AnyObject {
    var isAIInteractionActive: Bool { get }
    var hasNavigableTextSelection: Bool { get }
    var hasSearchTextTarget: Bool { get }
    var isPageOverviewActive: Bool { get }
    var isWordJumpActive: Bool { get }
    var documentKey: String? { get }

    func snapshot() -> ReaderSnapshot?
    func focus()
    func beginPageOverview() -> Bool
    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool
    func finishPageOverview()
    func cancelPageOverview()
    func beginSearchCommand()
    func beginWordJumpCommand()
    func beginLinkJumpCommand()
    func handleWordJumpKey(_ event: NSEvent) -> Bool
    func cancelWordJump()
    func handleAIKeyEvent(_ event: NSEvent) -> Bool
    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool
    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool
    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType, count: Int) -> Bool
    func vimDeleteHighlightsForSelection() -> Bool
    func vimScroll(x: CGFloat, y: CGFloat)
    func vimMoveByPage(_ delta: Int)
    func vimGoToFirstPage()
    func vimGoToLastPage()
    func vimGoToPage(_ pageNumber: Int)
    func vimGoToDestination(_ destination: PDFDestination)
    func vimPerformPDFAction(_ action: PDFAction)
    func vimJumpBack()
    func vimJumpForward()
    func vimSearchNext()
    func vimSearchPrevious()
    func vimSearchBy(_ delta: Int)
    func vimMaterializeSearchSelection()
    func vimCopySelection()
    func vimHighlightSelection(color: NSColor)
    func highlightListItems() -> [HighlightListItem]
    func vimSelectHighlight(_ item: HighlightListItem)
    func vimNavigateHighlight(_ direction: Int)
    func vimExplainSelectedHighlight()
    func vimStartAIConversation()
    func aiExplanationHistoryItems() -> [AIExplanationHistoryItem]
    func showNotification(_ message: String)
    func restoreAIExplanation(_ item: AIExplanationHistoryItem)
    func restoreAIConversation(_ item: AIConversationHistoryItem)
    func vimZoom(by factor: CGFloat)
    func vimZoomToPageFit()
    func vimZoomToFit()
}

extension ReaderController {
    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType, count: Int) -> Bool {
        var handled = false
        for _ in 0..<max(0, min(count, VimInputController.maximumRepeatCount)) {
            guard handleTextSelectionKey(rawKey, eventType: eventType) else { break }
            handled = true
        }
        return handled
    }

    func vimSearchBy(_ delta: Int) {
        for _ in 0..<min(delta.magnitude, UInt(VimInputController.maximumRepeatCount)) {
            if delta > 0 { vimSearchNext() } else { vimSearchPrevious() }
        }
    }

    func highlightListItems() -> [HighlightListItem] { [] }
    func vimSelectHighlight(_ item: HighlightListItem) {}
    func vimNavigateHighlight(_ direction: Int) {}

    func cancelPageOverview() {
        finishPageOverview()
    }

    func vimPerformPDFAction(_ action: PDFAction) {
        if let action = action as? PDFActionGoTo {
            vimGoToDestination(action.destination)
        }
    }

    var documentKey: String? {
        nil
    }

    func aiExplanationHistoryItems() -> [AIExplanationHistoryItem] {
        []
    }

    func showNotification(_ message: String) {}

    func restoreAIExplanation(_ item: AIExplanationHistoryItem) {}

    func restoreAIConversation(_ item: AIConversationHistoryItem) {}
}

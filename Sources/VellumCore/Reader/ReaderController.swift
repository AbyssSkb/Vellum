@preconcurrency import AppKit
import PDFKit

@MainActor
protocol ReaderController: AnyObject {
    var isAIInteractionActive: Bool { get }
    var hasNavigableTextSelection: Bool { get }
    var hasSearchTextTarget: Bool { get }
    var isPageOverviewActive: Bool { get }

    func snapshot() -> ReaderSnapshot?
    func focus()
    func beginPageOverview() -> Bool
    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool
    func finishPageOverview()
    func beginSearchCommand()
    func handleAIKeyEvent(_ event: NSEvent) -> Bool
    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool
    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool
    func vimDeleteHighlightsForSelection() -> Bool
    func vimScroll(x: CGFloat, y: CGFloat)
    func vimMoveByPage(_ delta: Int)
    func vimGoToFirstPage()
    func vimGoToLastPage()
    func vimGoToPage(_ pageNumber: Int)
    func vimGoToDestination(_ destination: PDFDestination)
    func vimJumpBack()
    func vimJumpForward()
    func vimSearchNext()
    func vimSearchPrevious()
    func vimMaterializeSearchSelection()
    func vimCopySelection()
    func vimHighlightSelection(color: NSColor)
    func vimExplainSelectedHighlight()
    func vimStartAIConversation()
    func aiExplanationHistoryItems() -> [AIExplanationHistoryItem]
    func restoreAIExplanation(_ item: AIExplanationHistoryItem)
    func restoreAIConversation(_ item: AIConversationHistoryItem)
    func vimZoom(by factor: CGFloat)
    func vimZoomToPageFit()
    func vimZoomToFit()
}

extension ReaderController {
    func aiExplanationHistoryItems() -> [AIExplanationHistoryItem] {
        []
    }

    func restoreAIExplanation(_ item: AIExplanationHistoryItem) {}

    func restoreAIConversation(_ item: AIConversationHistoryItem) {}
}

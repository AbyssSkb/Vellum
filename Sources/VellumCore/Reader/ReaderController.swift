@preconcurrency import AppKit
import PDFKit

@MainActor
protocol ReaderController: AnyObject {
    var isAIInteractionActive: Bool { get }
    var hasNavigableTextSelection: Bool { get }
    var isPageOverviewActive: Bool { get }

    func snapshot() -> ReaderSnapshot?
    func focus()
    func beginPageOverview() -> Bool
    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool
    func finishPageOverview()
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
    func vimCopySelection()
    func vimHighlightSelection(color: NSColor)
    func vimExplainSelectedHighlight()
    func vimZoom(by factor: CGFloat)
    func vimZoomToPageFit()
    func vimZoomToFit()
}

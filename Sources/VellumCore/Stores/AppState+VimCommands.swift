@preconcurrency import AppKit

extension AppState: VimCommandTarget {
    func openPDFInCurrentTab() {
        openPanel(mode: DefaultOpenModePreference.saved().pdfOpenMode)
    }

    func openPDFInNewTabs() {
        openPanel(mode: .newTabs)
    }

    func scrollBy(x: CGFloat, y: CGFloat) {
        activeReaderController?.vimScroll(x: x, y: y)
    }

    func moveByPage(_ delta: Int) {
        activeReaderController?.vimMoveByPage(delta)
    }

    func goToFirstPage() {
        activeReaderController?.vimGoToFirstPage()
    }

    func goToLastPage() {
        activeReaderController?.vimGoToLastPage()
    }

    func goToPage(_ pageNumber: Int) {
        activeReaderController?.vimGoToPage(pageNumber)
    }

    func jumpBack() {
        activeReaderController?.vimJumpBack()
    }

    func jumpForward() {
        activeReaderController?.vimJumpForward()
    }

    func beginSearch() {
        activeReaderController?.beginSearchCommand()
    }

    func searchNext() {
        activeReaderController?.vimSearchNext()
    }

    func searchPrevious() {
        activeReaderController?.vimSearchPrevious()
    }

    func materializeSearchSelection() {
        activeReaderController?.vimMaterializeSearchSelection()
    }

    func copySelection() {
        activeReaderController?.vimCopySelection()
    }

    func highlightSelection() {
        activeReaderController?.vimHighlightSelection(color: selectedHighlightColor.annotationColor)
    }

    func cycleHighlightColor() {
        cycleHighlightColor(preserveFocus: false)
    }

    func explainHighlightSelection() {
        activeReaderController?.vimExplainSelectedHighlight()
    }

    func startAIConversation() {
        activeReaderController?.vimStartAIConversation()
    }

    func zoom(by factor: CGFloat) {
        activeReaderController?.vimZoom(by: factor)
    }

    func zoomToPageFit() {
        activeReaderController?.vimZoomToPageFit()
    }

    func zoomToFit() {
        activeReaderController?.vimZoomToFit()
    }
}

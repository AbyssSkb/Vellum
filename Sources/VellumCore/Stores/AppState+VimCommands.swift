@preconcurrency import AppKit

extension AppState: VimCommandTarget {
    func openPDFInCurrentTab() {
        openPanel(mode: .currentTab)
    }

    func openPDFInNewTabs() {
        openPanel(mode: .newTabs)
    }

    func scrollBy(x: CGFloat, y: CGFloat) {
        activePDFView?.vimScroll(x: x, y: y)
    }

    func moveByPage(_ delta: Int) {
        activePDFView?.vimMoveByPage(delta)
    }

    func goToFirstPage() {
        activePDFView?.vimGoToFirstPage()
    }

    func goToLastPage() {
        activePDFView?.vimGoToLastPage()
    }

    func goToPage(_ pageNumber: Int) {
        activePDFView?.vimGoToPage(pageNumber)
    }

    func jumpBack() {
        activePDFView?.vimJumpBack()
    }

    func jumpForward() {
        activePDFView?.vimJumpForward()
    }

    func highlightSelection() {
        activePDFView?.vimHighlightSelection(color: selectedHighlightColor.annotationColor)
    }

    func cycleHighlightColor() {
        cycleHighlightColor(preserveFocus: false)
    }

    func explainHighlightSelection() {
        activePDFView?.vimExplainSelectedHighlight()
    }

    func zoom(by factor: CGFloat) {
        activePDFView?.vimZoom(by: factor)
    }

    func zoomToPageFit() {
        activePDFView?.vimZoomToPageFit()
    }

    func zoomToFit() {
        activePDFView?.vimZoomToFit()
    }
}

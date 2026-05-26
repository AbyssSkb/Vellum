import Foundation

@MainActor
struct VimCommandDispatcher {
    func perform(_ command: VimCommand, in appState: AppState) {
        switch command {
        case .open:
            appState.openPanel(mode: .currentTab)
        case .openInNewTab:
            appState.openPanel(mode: .newTabs)
        case .closeTab:
            appState.closeSelectedTab()
        case .restoreClosedTab:
            appState.restoreClosedPDFTab()
        case .nextTab:
            appState.selectNextTab()
        case .previousTab:
            appState.selectPreviousTab()
        case .scrollDown:
            appState.activePDFView?.vimScroll(x: 0, y: -28)
        case .scrollUp:
            appState.activePDFView?.vimScroll(x: 0, y: 28)
        case .largeScrollDown:
            appState.activePDFView?.vimScroll(x: 0, y: -115)
        case .largeScrollUp:
            appState.activePDFView?.vimScroll(x: 0, y: 115)
        case .scrollLeft:
            appState.activePDFView?.vimScroll(x: -42, y: 0)
        case .scrollRight:
            appState.activePDFView?.vimScroll(x: 42, y: 0)
        case .pageDown:
            appState.activePDFView?.vimMoveByPage(1)
        case .pageUp:
            appState.activePDFView?.vimMoveByPage(-1)
        case .firstPage:
            appState.activePDFView?.vimGoToFirstPage()
        case .lastPage:
            appState.activePDFView?.vimGoToLastPage()
        case .jumpToPage(let pageNumber):
            appState.activePDFView?.vimGoToPage(pageNumber)
        case .jumpBack:
            appState.activePDFView?.vimJumpBack()
        case .jumpForward:
            appState.activePDFView?.vimJumpForward()
        case .toggleOutline:
            appState.toggleOutlineSidebar()
        case .highlightSelection:
            appState.activePDFView?.vimHighlightSelection(
                color: appState.selectedHighlightColor.annotationColor
            )
        case .cycleHighlightColor:
            appState.cycleHighlightColor()
        case .explainHighlightSelection:
            appState.activePDFView?.vimExplainSelectedHighlight()
        case .zoomIn:
            appState.activePDFView?.vimZoom(by: 1.04)
        case .zoomOut:
            appState.activePDFView?.vimZoom(by: 1 / 1.04)
        case .zoomPageFit:
            appState.activePDFView?.vimZoomToPageFit()
        case .zoomFit:
            appState.activePDFView?.vimZoomToFit()
        }
    }
}

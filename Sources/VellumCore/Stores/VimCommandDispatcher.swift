import Foundation

@MainActor
struct VimCommandDispatcher {
    func perform(_ command: VimCommand, on target: VimCommandTarget) {
        switch command {
        case .open:
            target.openPDFInCurrentTab()
        case .openInNewTab:
            target.openPDFInNewTabs()
        case .closeTab:
            target.closeSelectedTab()
        case .restoreClosedTab:
            target.restoreClosedPDFTab()
        case .nextTab:
            target.selectNextTab()
        case .previousTab:
            target.selectPreviousTab()
        case .showTabSwitcher:
            target.showTabSwitcher()
        case .scrollDown:
            target.scrollBy(x: 0, y: -VimCommandMetrics.lineScrollDelta)
        case .scrollUp:
            target.scrollBy(x: 0, y: VimCommandMetrics.lineScrollDelta)
        case .largeScrollDown:
            target.scrollBy(x: 0, y: -VimCommandMetrics.largeScrollDelta)
        case .largeScrollUp:
            target.scrollBy(x: 0, y: VimCommandMetrics.largeScrollDelta)
        case .extraLargeScrollDown:
            target.scrollBy(x: 0, y: -VimCommandMetrics.extraLargeScrollDelta)
        case .extraLargeScrollUp:
            target.scrollBy(x: 0, y: VimCommandMetrics.extraLargeScrollDelta)
        case .scrollLeft:
            target.scrollBy(x: -VimCommandMetrics.horizontalScrollDelta, y: 0)
        case .scrollRight:
            target.scrollBy(x: VimCommandMetrics.horizontalScrollDelta, y: 0)
        case .pageDown:
            target.moveByPage(1)
        case .pageUp:
            target.moveByPage(-1)
        case .firstPage:
            target.goToFirstPage()
        case .lastPage:
            target.goToLastPage()
        case .jumpToPage(let pageNumber):
            target.goToPage(pageNumber)
        case .jumpBack:
            target.jumpBack()
        case .jumpForward:
            target.jumpForward()
        case .beginSearch:
            target.beginSearch()
        case .searchNext:
            target.searchNext()
        case .searchPrevious:
            target.searchPrevious()
        case .materializeSearchSelection:
            target.materializeSearchSelection()
        case .toggleOutline:
            target.toggleOutlineSidebar()
        case .copySelection:
            target.copySelection()
        case .highlightSelection:
            target.highlightSelection()
        case .cycleHighlightColor:
            target.cycleHighlightColor()
        case .explainHighlightSelection:
            target.explainHighlightSelection()
        case .zoomIn:
            target.zoom(by: VimCommandMetrics.zoomStepFactor)
        case .zoomOut:
            target.zoom(by: 1 / VimCommandMetrics.zoomStepFactor)
        case .zoomPageFit:
            target.zoomToPageFit()
        case .zoomFit:
            target.zoomToFit()
        }
    }
}

@MainActor
protocol VimCommandTarget {
    func openPDFInCurrentTab()
    func openPDFInNewTabs()
    func closeSelectedTab()
    func restoreClosedPDFTab()
    func selectNextTab()
    func selectPreviousTab()
    func showTabSwitcher()
    func scrollBy(x: CGFloat, y: CGFloat)
    func moveByPage(_ delta: Int)
    func goToFirstPage()
    func goToLastPage()
    func goToPage(_ pageNumber: Int)
    func jumpBack()
    func jumpForward()
    func beginSearch()
    func searchNext()
    func searchPrevious()
    func materializeSearchSelection()
    func toggleOutlineSidebar()
    func copySelection()
    func highlightSelection()
    func cycleHighlightColor()
    func explainHighlightSelection()
    func zoom(by factor: CGFloat)
    func zoomToPageFit()
    func zoomToFit()
}

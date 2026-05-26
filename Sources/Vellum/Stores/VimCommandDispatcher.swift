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
        case .scrollDown:
            target.scrollBy(x: 0, y: -28)
        case .scrollUp:
            target.scrollBy(x: 0, y: 28)
        case .largeScrollDown:
            target.scrollBy(x: 0, y: -115)
        case .largeScrollUp:
            target.scrollBy(x: 0, y: 115)
        case .scrollLeft:
            target.scrollBy(x: -42, y: 0)
        case .scrollRight:
            target.scrollBy(x: 42, y: 0)
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
        case .toggleOutline:
            target.toggleOutlineSidebar()
        case .highlightSelection:
            target.highlightSelection()
        case .cycleHighlightColor:
            target.cycleHighlightColor()
        case .explainHighlightSelection:
            target.explainHighlightSelection()
        case .zoomIn:
            target.zoom(by: 1.04)
        case .zoomOut:
            target.zoom(by: 1 / 1.04)
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
    func scrollBy(x: CGFloat, y: CGFloat)
    func moveByPage(_ delta: Int)
    func goToFirstPage()
    func goToLastPage()
    func goToPage(_ pageNumber: Int)
    func jumpBack()
    func jumpForward()
    func toggleOutlineSidebar()
    func highlightSelection()
    func cycleHighlightColor()
    func explainHighlightSelection()
    func zoom(by factor: CGFloat)
    func zoomToPageFit()
    func zoomToFit()
}

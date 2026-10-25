import Foundation

@MainActor
struct VimCommandDispatcher {
    func perform(_ command: VimCommand, on target: VimCommandTarget) {
        perform(command, count: 1, on: target)
    }

    private func perform(_ command: VimCommand, count: Int, on target: VimCommandTarget) {
        switch command {
        case .counted(let command, let requestedCount):
            let count = min(max(requestedCount, 1), VimInputController.maximumRepeatCount)
            perform(command, count: command.acceptsCount ? count : 1, on: target)
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
        case .showPDFQuickOpen:
            target.showPDFQuickOpen()
        case .scrollDown:
            target.scrollBy(x: 0, y: -VimCommandMetrics.lineScrollDelta * CGFloat(count))
        case .scrollUp:
            target.scrollBy(x: 0, y: VimCommandMetrics.lineScrollDelta * CGFloat(count))
        case .largeScrollDown:
            target.scrollBy(x: 0, y: -VimCommandMetrics.largeScrollDelta * CGFloat(count))
        case .largeScrollUp:
            target.scrollBy(x: 0, y: VimCommandMetrics.largeScrollDelta * CGFloat(count))
        case .extraLargeScrollDown:
            target.scrollBy(x: 0, y: -VimCommandMetrics.extraLargeScrollDelta * CGFloat(count))
        case .extraLargeScrollUp:
            target.scrollBy(x: 0, y: VimCommandMetrics.extraLargeScrollDelta * CGFloat(count))
        case .scrollLeft:
            target.scrollBy(x: -VimCommandMetrics.horizontalScrollDelta * CGFloat(count), y: 0)
        case .scrollRight:
            target.scrollBy(x: VimCommandMetrics.horizontalScrollDelta * CGFloat(count), y: 0)
        case .pageDown:
            target.moveByPage(count)
        case .pageUp:
            target.moveByPage(-count)
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
        case .searchSelectedText:
            target.searchSelectedText()
        case .beginWordJump:
            target.beginWordJump()
        case .beginLinkJump:
            target.beginLinkJump()
        case .beginLinkPreview:
            target.beginLinkPreview()
        case .searchNext:
            if count == 1 { target.searchNext() } else { target.searchBy(count) }
        case .searchPrevious:
            if count == 1 { target.searchPrevious() } else { target.searchBy(-count) }
        case .restoreTextSelection:
            target.restoreTextSelection()
        case .materializeSearchSelection:
            target.materializeSearchSelection()
        case .toggleOutline:
            target.toggleOutlineSidebar()
        case .copySelection:
            target.copySelection()
        case .highlightSelection:
            target.highlightSelection()
        case .showHighlights:
            target.showHighlights()
        case .nextHighlight:
            target.nextHighlight()
        case .previousHighlight:
            target.previousHighlight()
        case .cycleHighlightColor:
            target.cycleHighlightColor()
        case .explainHighlightSelection:
            target.explainHighlightSelection()
        case .startAIConversation:
            target.startAIConversation()
        case .showAIExplanationHistory:
            target.showAIExplanationHistory()
        case .showAIConversationHistory:
            target.showAIConversationHistory()
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
    func showPDFQuickOpen()
    func scrollBy(x: CGFloat, y: CGFloat)
    func moveByPage(_ delta: Int)
    func goToFirstPage()
    func goToLastPage()
    func goToPage(_ pageNumber: Int)
    func jumpBack()
    func jumpForward()
    func beginSearch()
    func searchSelectedText()
    func beginWordJump()
    func beginLinkJump()
    func beginLinkPreview()
    func searchNext()
    func searchPrevious()
    func searchBy(_ delta: Int)
    func restoreTextSelection()
    func materializeSearchSelection()
    func toggleOutlineSidebar()
    func copySelection()
    func highlightSelection()
    func showHighlights()
    func nextHighlight()
    func previousHighlight()
    func cycleHighlightColor()
    func explainHighlightSelection()
    func startAIConversation()
    func showAIExplanationHistory()
    func showAIConversationHistory()
    func zoom(by factor: CGFloat)
    func zoomToPageFit()
    func zoomToFit()
}

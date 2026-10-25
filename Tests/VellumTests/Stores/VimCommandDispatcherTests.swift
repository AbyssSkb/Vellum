import Foundation
import Testing
@testable import VellumCore

@MainActor
@Suite("Vim command dispatcher")
struct VimCommandDispatcherTests {
    @Test
    func appCommandsRouteToTabAndOpenActions() {
        let dispatcher = VimCommandDispatcher()
        let target = RecordingVimCommandTarget()

        dispatcher.perform(.open, on: target)
        dispatcher.perform(.openInNewTab, on: target)
        dispatcher.perform(.closeTab, on: target)
        dispatcher.perform(.restoreClosedTab, on: target)
        dispatcher.perform(.nextTab, on: target)
        dispatcher.perform(.previousTab, on: target)
        dispatcher.perform(.showTabSwitcher, on: target)
        dispatcher.perform(.showPDFQuickOpen, on: target)

        #expect(target.actions == [
            .openCurrent,
            .openNewTabs,
            .closeTab,
            .restoreClosedTab,
            .nextTab,
            .previousTab,
            .showTabSwitcher,
            .showPDFQuickOpen
        ])
    }

    @Test
    func readerNavigationCommandsRouteToReaderActions() {
        let dispatcher = VimCommandDispatcher()
        let target = RecordingVimCommandTarget()

        dispatcher.perform(.scrollDown, on: target)
        dispatcher.perform(.scrollUp, on: target)
        dispatcher.perform(.largeScrollDown, on: target)
        dispatcher.perform(.largeScrollUp, on: target)
        dispatcher.perform(.extraLargeScrollDown, on: target)
        dispatcher.perform(.extraLargeScrollUp, on: target)
        dispatcher.perform(.scrollLeft, on: target)
        dispatcher.perform(.scrollRight, on: target)
        dispatcher.perform(.pageDown, on: target)
        dispatcher.perform(.pageUp, on: target)
        dispatcher.perform(.firstPage, on: target)
        dispatcher.perform(.lastPage, on: target)
        dispatcher.perform(.jumpToPage(42), on: target)
        dispatcher.perform(.jumpBack, on: target)
        dispatcher.perform(.jumpForward, on: target)
        dispatcher.perform(.beginSearch, on: target)
        dispatcher.perform(.searchSelectedText, on: target)
        dispatcher.perform(.beginWordJump, on: target)
        dispatcher.perform(.beginLinkJump, on: target)
        dispatcher.perform(.beginLinkPreview, on: target)
        dispatcher.perform(.searchNext, on: target)
        dispatcher.perform(.searchPrevious, on: target)
        dispatcher.perform(.restoreTextSelection, on: target)
        dispatcher.perform(.materializeSearchSelection, on: target)

        let expectedActions: [RecordingVimCommandTarget.Action] = [
            .scroll(x: 0, y: -VimCommandMetrics.lineScrollDelta),
            .scroll(x: 0, y: VimCommandMetrics.lineScrollDelta),
            .scroll(x: 0, y: -VimCommandMetrics.largeScrollDelta),
            .scroll(x: 0, y: VimCommandMetrics.largeScrollDelta),
            .scroll(x: 0, y: -VimCommandMetrics.extraLargeScrollDelta),
            .scroll(x: 0, y: VimCommandMetrics.extraLargeScrollDelta),
            .scroll(x: -VimCommandMetrics.horizontalScrollDelta, y: 0),
            .scroll(x: VimCommandMetrics.horizontalScrollDelta, y: 0),
            .moveByPage(1),
            .moveByPage(-1),
            .firstPage,
            .lastPage,
            .goToPage(42),
            .jumpBack,
            .jumpForward,
            .beginSearch,
            .searchSelectedText,
            .beginWordJump,
            .beginLinkJump,
            .beginLinkPreview,
            .searchNext,
            .searchPrevious,
            .restoreTextSelection,
            .materializeSearchSelection
        ]
        #expect(target.actions == expectedActions)
    }

    @Test
    func annotationAndZoomCommandsRouteToReaderActions() {
        let dispatcher = VimCommandDispatcher()
        let target = RecordingVimCommandTarget()

        dispatcher.perform(.toggleOutline, on: target)
        dispatcher.perform(.copySelection, on: target)
        dispatcher.perform(.highlightSelection, on: target)
        dispatcher.perform(.showHighlights, on: target)
        dispatcher.perform(.nextHighlight, on: target)
        dispatcher.perform(.previousHighlight, on: target)
        dispatcher.perform(.cycleHighlightColor, on: target)
        dispatcher.perform(.explainHighlightSelection, on: target)
        dispatcher.perform(.startAIConversation, on: target)
        dispatcher.perform(.lookupDictionary, on: target)
        dispatcher.perform(.showAIExplanationHistory, on: target)
        dispatcher.perform(.showAIConversationHistory, on: target)
        dispatcher.perform(.zoomIn, on: target)
        dispatcher.perform(.zoomOut, on: target)
        dispatcher.perform(.zoomPageFit, on: target)
        dispatcher.perform(.zoomFit, on: target)

        #expect(target.actions == [
            .toggleOutline,
            .copySelection,
            .highlightSelection,
            .showHighlights,
            .nextHighlight,
            .previousHighlight,
            .cycleHighlightColor,
            .explainHighlightSelection,
            .startAIConversation,
            .lookupDictionary,
            .showAIExplanationHistory,
            .showAIConversationHistory,
            .zoom(VimCommandMetrics.zoomStepFactor),
            .zoom(1 / VimCommandMetrics.zoomStepFactor),
            .zoomPageFit,
            .zoomFit
        ])
    }

    @Test
    func countedNavigationUsesOneCombinedReaderAction() {
        let dispatcher = VimCommandDispatcher()
        let target = RecordingVimCommandTarget()
        dispatcher.perform(.counted(.pageDown, 5), on: target)
        dispatcher.perform(.counted(.pageUp, 4), on: target)
        dispatcher.perform(.counted(.scrollDown, 10), on: target)
        dispatcher.perform(.counted(.searchNext, 3), on: target)
        dispatcher.perform(.counted(.searchPrevious, 2), on: target)
        #expect(target.actions == [
            .moveByPage(5), .moveByPage(-4),
            .scroll(x: 0, y: -VimCommandMetrics.lineScrollDelta * 10),
            .searchBy(3), .searchBy(-2)
        ])
    }

    @Test
    func hugeCountsAreBoundedAndActionsAreNeverRepeated() {
        let dispatcher = VimCommandDispatcher()
        let target = RecordingVimCommandTarget()
        dispatcher.perform(.counted(.pageDown, Int.max), on: target)
        dispatcher.perform(.counted(.closeTab, 5), on: target)
        dispatcher.perform(.counted(.showPDFQuickOpen, 5), on: target)
        #expect(target.actions == [.moveByPage(VimInputController.maximumRepeatCount), .closeTab, .showPDFQuickOpen])
    }
}

@MainActor
private final class RecordingVimCommandTarget: VimCommandTarget {
    private(set) var actions: [Action] = []

    func openPDFInCurrentTab() {
        actions.append(.openCurrent)
    }

    func openPDFInNewTabs() {
        actions.append(.openNewTabs)
    }

    func closeSelectedTab() {
        actions.append(.closeTab)
    }

    func restoreClosedPDFTab() {
        actions.append(.restoreClosedTab)
    }

    func selectNextTab() {
        actions.append(.nextTab)
    }

    func selectPreviousTab() {
        actions.append(.previousTab)
    }

    func showTabSwitcher() {
        actions.append(.showTabSwitcher)
    }

    func showPDFQuickOpen() {
        actions.append(.showPDFQuickOpen)
    }

    func scrollBy(x: CGFloat, y: CGFloat) {
        actions.append(.scroll(x: x, y: y))
    }

    func moveByPage(_ delta: Int) {
        actions.append(.moveByPage(delta))
    }

    func goToFirstPage() {
        actions.append(.firstPage)
    }

    func goToLastPage() {
        actions.append(.lastPage)
    }

    func goToPage(_ pageNumber: Int) {
        actions.append(.goToPage(pageNumber))
    }

    func jumpBack() {
        actions.append(.jumpBack)
    }

    func jumpForward() {
        actions.append(.jumpForward)
    }

    func beginSearch() {
        actions.append(.beginSearch)
    }

    func beginWordJump() {
        actions.append(.beginWordJump)
    }

    func beginLinkJump() {
        actions.append(.beginLinkJump)
    }

    func beginLinkPreview() {
        actions.append(.beginLinkPreview)
    }

    func searchSelectedText() {
        actions.append(.searchSelectedText)
    }

    func searchNext() {
        actions.append(.searchNext)
    }

    func searchPrevious() {
        actions.append(.searchPrevious)
    }

    func searchBy(_ delta: Int) {
        actions.append(.searchBy(delta))
    }

    func restoreTextSelection() {
        actions.append(.restoreTextSelection)
    }

    func materializeSearchSelection() {
        actions.append(.materializeSearchSelection)
    }

    func toggleOutlineSidebar() {
        actions.append(.toggleOutline)
    }

    func copySelection() {
        actions.append(.copySelection)
    }

    func highlightSelection() {
        actions.append(.highlightSelection)
    }

    func showHighlights() {
        actions.append(.showHighlights)
    }

    func nextHighlight() {
        actions.append(.nextHighlight)
    }

    func previousHighlight() {
        actions.append(.previousHighlight)
    }

    func cycleHighlightColor() {
        actions.append(.cycleHighlightColor)
    }

    func explainHighlightSelection() {
        actions.append(.explainHighlightSelection)
    }

    func startAIConversation() {
        actions.append(.startAIConversation)
    }

    func lookupDictionary() {
        actions.append(.lookupDictionary)
    }

    func showAIExplanationHistory() {
        actions.append(.showAIExplanationHistory)
    }

    func showAIConversationHistory() {
        actions.append(.showAIConversationHistory)
    }

    func zoom(by factor: CGFloat) {
        actions.append(.zoom(factor))
    }

    func zoomToPageFit() {
        actions.append(.zoomPageFit)
    }

    func zoomToFit() {
        actions.append(.zoomFit)
    }

    enum Action: Equatable {
        case openCurrent
        case openNewTabs
        case closeTab
        case restoreClosedTab
        case nextTab
        case previousTab
        case showTabSwitcher
        case showPDFQuickOpen
        case scroll(x: CGFloat, y: CGFloat)
        case moveByPage(Int)
        case firstPage
        case lastPage
        case goToPage(Int)
        case jumpBack
        case jumpForward
        case beginSearch
        case searchSelectedText
        case beginWordJump
        case beginLinkJump
        case beginLinkPreview
        case searchNext
        case searchPrevious
        case searchBy(Int)
        case restoreTextSelection
        case materializeSearchSelection
        case toggleOutline
        case copySelection
        case highlightSelection
        case showHighlights
        case nextHighlight
        case previousHighlight
        case cycleHighlightColor
        case explainHighlightSelection
        case startAIConversation
        case lookupDictionary
        case showAIExplanationHistory
        case showAIConversationHistory
        case zoom(CGFloat)
        case zoomPageFit
        case zoomFit
    }
}

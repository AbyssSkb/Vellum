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

        #expect(target.actions == [
            .openCurrent,
            .openNewTabs,
            .closeTab,
            .restoreClosedTab,
            .nextTab,
            .previousTab
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
        dispatcher.perform(.scrollLeft, on: target)
        dispatcher.perform(.scrollRight, on: target)
        dispatcher.perform(.pageDown, on: target)
        dispatcher.perform(.pageUp, on: target)
        dispatcher.perform(.firstPage, on: target)
        dispatcher.perform(.lastPage, on: target)
        dispatcher.perform(.jumpToPage(42), on: target)
        dispatcher.perform(.jumpBack, on: target)
        dispatcher.perform(.jumpForward, on: target)

        #expect(target.actions == [
            .scroll(x: 0, y: -VimCommandMetrics.lineScrollDelta),
            .scroll(x: 0, y: VimCommandMetrics.lineScrollDelta),
            .scroll(x: 0, y: -VimCommandMetrics.largeScrollDelta),
            .scroll(x: 0, y: VimCommandMetrics.largeScrollDelta),
            .scroll(x: -VimCommandMetrics.horizontalScrollDelta, y: 0),
            .scroll(x: VimCommandMetrics.horizontalScrollDelta, y: 0),
            .moveByPage(1),
            .moveByPage(-1),
            .firstPage,
            .lastPage,
            .goToPage(42),
            .jumpBack,
            .jumpForward
        ])
    }

    @Test
    func annotationAndZoomCommandsRouteToReaderActions() {
        let dispatcher = VimCommandDispatcher()
        let target = RecordingVimCommandTarget()

        dispatcher.perform(.toggleOutline, on: target)
        dispatcher.perform(.highlightSelection, on: target)
        dispatcher.perform(.cycleHighlightColor, on: target)
        dispatcher.perform(.explainHighlightSelection, on: target)
        dispatcher.perform(.zoomIn, on: target)
        dispatcher.perform(.zoomOut, on: target)
        dispatcher.perform(.zoomPageFit, on: target)
        dispatcher.perform(.zoomFit, on: target)

        #expect(target.actions == [
            .toggleOutline,
            .highlightSelection,
            .cycleHighlightColor,
            .explainHighlightSelection,
            .zoom(VimCommandMetrics.zoomStepFactor),
            .zoom(1 / VimCommandMetrics.zoomStepFactor),
            .zoomPageFit,
            .zoomFit
        ])
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

    func toggleOutlineSidebar() {
        actions.append(.toggleOutline)
    }

    func highlightSelection() {
        actions.append(.highlightSelection)
    }

    func cycleHighlightColor() {
        actions.append(.cycleHighlightColor)
    }

    func explainHighlightSelection() {
        actions.append(.explainHighlightSelection)
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
        case scroll(x: CGFloat, y: CGFloat)
        case moveByPage(Int)
        case firstPage
        case lastPage
        case goToPage(Int)
        case jumpBack
        case jumpForward
        case toggleOutline
        case highlightSelection
        case cycleHighlightColor
        case explainHighlightSelection
        case zoom(CGFloat)
        case zoomPageFit
        case zoomFit
    }
}

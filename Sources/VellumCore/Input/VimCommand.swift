enum VimCommand: Equatable, Sendable {
    indirect case counted(VimCommand, Int)
    case open
    case openInNewTab
    case closeTab
    case restoreClosedTab
    case nextTab
    case previousTab
    case showTabSwitcher
    case scrollDown
    case scrollUp
    case largeScrollDown
    case largeScrollUp
    case scrollLeft
    case scrollRight
    case pageDown
    case pageUp
    case extraLargeScrollDown
    case extraLargeScrollUp
    case firstPage
    case lastPage
    case jumpToPage(Int)
    case jumpBack
    case jumpForward
    case beginSearch
    case beginWordJump
    case beginLinkJump
    case searchNext
    case searchPrevious
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
    case showAIExplanationHistory
    case showAIConversationHistory
    case zoomIn
    case zoomOut
    case zoomPageFit
    case zoomFit

    var acceptsCount: Bool {
        switch self {
        case .scrollDown, .scrollUp, .largeScrollDown, .largeScrollUp,
             .extraLargeScrollDown, .extraLargeScrollUp, .scrollLeft, .scrollRight,
             .pageDown, .pageUp, .searchNext, .searchPrevious:
            return true
        default:
            return false
        }
    }
}

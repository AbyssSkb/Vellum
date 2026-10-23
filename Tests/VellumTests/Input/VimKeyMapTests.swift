import Testing
@testable import VellumCore

@Suite("Vim key map")
struct VimKeyMapTests {
    @Test
    func tabGestureDoesNotShareTheSidebarToggleCommand() {
        #expect(VimKeyMap.command(for: "\t") == nil)
        #expect(VimKeyMap.command(for: "t") == .toggleOutline)
    }

    @Test
    func plusNormalizesToZoomInContinuousKey() {
        #expect(VimKeyMap.normalizedContinuousKey("+") == "=")
        #expect(VimKeyMap.isContinuousKey("+"))
        #expect(VimKeyMap.continuousCommand(for: "=") == .zoomIn)
    }

    @Test(arguments: [("D", VimCommand.extraLargeScrollDown), ("U", .extraLargeScrollUp)])
    func uppercaseExtraLargeScrollKeysRemainContinuous(key: String, command: VimCommand) {
        #expect(VimKeyMap.normalizedContinuousKey(key) == key)
        #expect(VimKeyMap.isContinuousKey(key))
        #expect(VimKeyMap.continuousCommand(for: key) == command)
    }

    @Test(arguments: ["w", "e", "^", "$"])
    func selectionMotionKeysDependOnNavigableSelection(key: String) {
        #expect(!VimKeyMap.isHandledKey(key, hasNavigableTextSelection: false, hasTextActionTarget: true))
        #expect(VimKeyMap.isHandledKey(key, hasNavigableTextSelection: true, hasTextActionTarget: true))
    }

    @Test
    func copyKeyIsHandledWithoutATextActionTarget() {
        #expect(VimKeyMap.isHandledKey("y", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.isHandledKey("y", hasNavigableTextSelection: false, hasTextActionTarget: true))
        #expect(VimKeyMap.command(for: "y") == .copySelection)
    }

    @Test
    func conversationKeyRoutesToAIConversation() {
        #expect(VimKeyMap.isHandledKey("i", hasNavigableTextSelection: false, hasTextActionTarget: true))
        #expect(VimKeyMap.command(for: "i") == .startAIConversation)
        #expect(VimKeyMap.isHandledKey("I", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "I") == .showAIConversationHistory)
        #expect(VimKeyMap.lowercaseFallback(for: "I") == nil)
    }

    @Test
    func explanationHistoryKeyRoutesToAIExplanationHistory() {
        #expect(VimKeyMap.isHandledKey("A", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "A") == .showAIExplanationHistory)
        #expect(VimKeyMap.lowercaseFallback(for: "A") == nil)
    }

    @Test
    func searchKeysAreHandledWithoutSelection() {
        #expect(VimKeyMap.isHandledKey("/", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.isHandledKey("n", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.isHandledKey("N", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "/") == .beginSearch)
        #expect(VimKeyMap.isHandledKey("*", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "*") == .searchSelectedText)
        #expect(VimKeyMap.repeatableCommand(for: "*") == nil)
        #expect(VimKeyMap.command(for: "n") == .searchNext)
        #expect(VimKeyMap.command(for: "N") == .searchPrevious)
        #expect(VimKeyMap.repeatableCommand(for: "n") == .searchNext)
        #expect(VimKeyMap.repeatableCommand(for: "N") == .searchPrevious)
    }

    @Test
    func wordJumpUsesOnlyLowercaseSWithoutRequiringASelection() {
        #expect(VimKeyMap.isHandledKey("s", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "s") == .beginWordJump)
        #expect(!VimKeyMap.isContinuousKey("s"))
        #expect(!VimKeyMap.isHandledKey("S", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "S") == nil)
        #expect(VimKeyMap.lowercaseFallback(for: "S") == nil)
    }

    @Test
    func uppercaseFStartsLinkHintsAndLowercaseFStillTurnsThePage() {
        #expect(VimKeyMap.command(for: "F") == .beginLinkJump)
        #expect(VimKeyMap.command(for: "f") == .pageDown)
        #expect(VimKeyMap.lowercaseFallback(for: "F") == nil)
        #expect(VimKeyMap.isHandledKey("F", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(!VimKeyMap.isContinuousKey("F"))
    }

    @Test
    func uppercaseMOpensHighlightsWithoutAddingAHighlight() {
        #expect(VimKeyMap.command(for: "M") == .showHighlights)
        #expect(VimKeyMap.command(for: "m") == .highlightSelection)
        #expect(VimKeyMap.lowercaseFallback(for: "M") == nil)
        #expect(VimKeyMap.isHandledKey("M", hasNavigableTextSelection: false, hasTextActionTarget: false))
    }

    @Test
    func materializeSearchSelectionKeyIsHandledWithoutSelection() {
        #expect(VimKeyMap.isHandledKey("v", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "v") == .materializeSearchSelection)
    }

    @Test
    func uppercaseTOpensTabSwitcher() {
        #expect(VimKeyMap.isHandledKey("T", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "T") == .showTabSwitcher)
    }

    @Test
    func uppercaseFallbackLeavesDedicatedUppercaseCommandsAlone() {
        #expect(VimKeyMap.lowercaseFallback(for: "G") == nil)
        #expect(VimKeyMap.lowercaseFallback(for: "N") == "n")
    }
}

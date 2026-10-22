import Testing
@testable import VellumCore

@Suite("Vim input controller")
struct VimInputControllerTests {
    @Test
    func numericPrefixRejectsLeadingZeroAndConsumesValue() {
        var state = VimKeyState()

        let leadingZeroHandled = state.handleNumericPrefixKey("0")
        let oneHandled = state.handleNumericPrefixKey("1")
        let trailingZeroHandled = state.handleNumericPrefixKey("0")
        let consumedPrefix = state.consumeNumericPrefix()

        #expect(!leadingZeroHandled)
        #expect(oneHandled)
        #expect(trailingZeroHandled)
        #expect(consumedPrefix == 10)
        #expect(state.numericPrefix.isEmpty)
    }

    @Test
    func pendingGCommandRoutesToFirstPage() {
        var input = VimInputController()

        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.firstPage))
    }

    @Test
    func numericPrefixGCommandRoutesToPage() {
        var input = VimInputController()

        #expect(input.handleKeyDown("1", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.jumpToPage(12)))
    }

    @Test(arguments: [1, 10, 12])
    func numericPrefixGGCommandRoutesToPageAndConsumesTheCount(pageNumber: Int) {
        var input = VimInputController()

        for digit in String(pageNumber) {
            #expect(input.handleKeyDown(String(digit), isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        }
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.jumpToPage(pageNumber)))
        #expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.lastPage))
    }

    @Test
    func continuousCommandCancelsPendingGCommand() {
        var input = VimInputController()

        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("j", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("j"))
        #expect(input.handleKeyUp("j") == .stopContinuousKey)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.firstPage))
    }

    @Test
    func continuousCommandConsumesNumericPrefixAsOneCountedMove() {
        var input = VimInputController()

        #expect(input.handleKeyDown("1", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("j", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.counted(.scrollDown, 12)))
        #expect(input.handleKeyUp("j") == .ignored)
        #expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.lastPage))
    }

    @Test(arguments: [
        ("G", VimCommand.lastPage),
        ("H", .previousTab),
        ("L", .nextTab),
        ("X", .restoreClosedTab),
        ("O", .openInNewTab)
    ])
    func uppercaseCommandCancelsPendingGCommand(key: String, command: VimCommand) {
        var input = VimInputController()

        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(command))
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.firstPage))
    }

    @Test(arguments: ["G", "H", "L", "X", "O"])
    func uppercaseCommandsIgnoreNativeRepeats(key: String) {
        var input = VimInputController()

        #expect(input.handleKeyDown(key, isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
    }

    @Test
    func continuousKeyStartsRepeatsAndStops() {
        var input = VimInputController()

        #expect(input.handleKeyDown("j", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("j"))
        #expect(input.handleKeyDown("j", isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyUp("j") == .stopContinuousKey)
        #expect(input.heldKey == nil)
    }

    @Test(arguments: ["D", "U"])
    func uppercaseContinuousScrollKeysRemainUppercase(key: String) {
        var input = VimInputController()

        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey(key))
        #expect(input.handleKeyDown(key, isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyUp(key) == .stopContinuousKey)
        #expect(input.heldKey == nil)
    }

    @Test(arguments: [("D", "d"), ("U", "u"), ("d", "D"), ("u", "U")])
    func continuousScrollStopsWhenShiftChangesBeforeRelease(key: String, releasedKey: String) {
        var input = VimInputController()

        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey(key))
        #expect(input.handleKeyUp(releasedKey) == .stopContinuousKey)
        #expect(input.heldKey == nil)
    }

    @Test
    func copySelectionOnlyRoutesWhenThereIsATextActionTarget() {
        var input = VimInputController()

        #expect(input.handleKeyDown("y", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .ignored)
        #expect(input.handleKeyDown("y", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: true) == .command(.copySelection))
    }

    @Test(arguments: [
        ("/", VimCommand.beginSearch),
        ("v", .materializeSearchSelection),
        ("T", .showTabSwitcher)
    ])
    func searchAndSwitcherCommandsClearNumericInput(key: String, command: VimCommand) {
        var input = VimInputController()

        #expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(command))
        #expect(input.state.numericPrefix.isEmpty)
        #expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.lastPage))
    }

    @Test
    func wordJumpStartsOnceAndClearsNumericInput() {
        var input = VimInputController()
        #expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("s", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.beginWordJump))
        #expect(input.state.numericPrefix.isEmpty)
        #expect(input.handleKeyDown("s", isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("S", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .ignored)
    }

    @Test
    func pendingGChangesUppercaseTToPreviousTab() {
        var input = VimInputController()

        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("T", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.previousTab))
        #expect(input.handleKeyDown("T", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.showTabSwitcher))
    }

    @Test(arguments: [("n", VimCommand.searchNext), ("N", .searchPrevious)])
    func searchNavigationRepeatsClearPendingInput(key: String, command: VimCommand) {
        var input = VimInputController()

        #expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown(key, isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(command))
        #expect(input.state.pendingKey == nil)
        #expect(input.state.numericPrefix.isEmpty)
        #expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.lastPage))
    }

    @Test(arguments: [
        ("n", VimCommand.searchNext), ("N", .searchPrevious),
        ("f", .pageDown), ("b", .pageUp), (" ", .pageDown),
        ("j", .scrollDown), ("k", .scrollUp), ("h", .scrollLeft), ("l", .scrollRight),
        ("d", .largeScrollDown), ("u", .largeScrollUp),
        ("D", .extraLargeScrollDown), ("U", .extraLargeScrollUp)
    ])
    func navigationCommandsConsumeCounts(key: String, command: VimCommand) {
        var input = VimInputController()
        _ = input.handleKey("3")
        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.counted(command, 3)))
        #expect(input.state.numericPrefix.isEmpty)
        #expect(input.handleKey("G") == .command(.lastPage))
    }

    @Test(arguments: ["9999", String(repeating: "9", count: 30)])
    func repeatCountsAreBoundedEvenWhenIntegerParsingOverflows(prefix: String) {
        var input = VimInputController()
        for digit in prefix { _ = input.handleKey(String(digit)) }
        #expect(input.handleKey("n") == .command(.counted(.searchNext, VimInputController.maximumRepeatCount)))
    }

    @Test(arguments: [("m", VimCommand.highlightSelection), ("x", .closeTab), ("o", .open), ("F", .beginLinkJump)])
    func actionCommandsExecuteOnlyOnceAndConsumeCounts(key: String, command: VimCommand) {
        var input = VimInputController()
        _ = input.handleKey("9")
        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(command))
        #expect(input.state.numericPrefix.isEmpty)
    }

    @Test(arguments: [("m", VimCommand.showHighlights), ("n", .nextHighlight), ("N", .previousHighlight), ("t", .nextTab), ("T", .previousTab)])
    func gPrefixRoutesNavigationWithoutTriggeringTheBareKey(key: String, command: VimCommand) {
        var input = VimInputController()
        _ = input.handleKey("g")
        #expect(input.handleKeyDown(key, isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(command))
        #expect(input.state.pendingKey == nil)
    }
}

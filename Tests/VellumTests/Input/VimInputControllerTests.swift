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

    @Test
    func continuousKeyStartsRepeatsAndStops() {
        var input = VimInputController()

        #expect(input.handleKeyDown("j", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("j"))
        #expect(input.handleKeyDown("j", isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyUp("j") == .stopContinuousKey)
        #expect(input.heldKey == nil)
    }

    @Test
    func uppercaseContinuousScrollKeysRemainUppercase() {
        var input = VimInputController()

        #expect(input.handleKeyDown("D", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("D"))
        #expect(input.handleKeyDown("D", isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyUp("D") == .stopContinuousKey)

        #expect(input.handleKeyDown("U", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("U"))
        #expect(input.handleKeyUp("U") == .stopContinuousKey)
    }

    @Test
    func uppercaseContinuousScrollStopsWhenShiftIsReleasedFirst() {
        var input = VimInputController()

        #expect(input.handleKeyDown("D", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("D"))
        #expect(input.handleKeyUp("d") == .stopContinuousKey)
        #expect(input.heldKey == nil)

        #expect(input.handleKeyDown("U", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .continuousKey("U"))
        #expect(input.handleKeyUp("u") == .stopContinuousKey)
        #expect(input.heldKey == nil)
    }

    @Test
    func copySelectionOnlyRoutesWhenSelectionIsNavigable() {
        var input = VimInputController()

        #expect(input.handleKeyDown("y", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .ignored)
        #expect(input.handleKeyDown("y", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: true) == .command(.copySelection))
    }

    @Test
    func searchCommandsRouteWithoutSelection() {
        var input = VimInputController()

        #expect(input.handleKeyDown("/", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.beginSearch))
        #expect(input.handleKeyDown("n", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.searchNext))
        #expect(input.handleKeyDown("N", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.searchPrevious))
        #expect(input.handleKeyDown("v", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.materializeSearchSelection))
    }

    @Test
    func uppercaseTOpensTabSwitcherButGTStillRoutesPreviousTab() {
        var input = VimInputController()

        #expect(input.handleKeyDown("T", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.showTabSwitcher))
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .handled)
        #expect(input.handleKeyDown("T", isRepeat: false, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.previousTab))
    }

    @Test
    func searchNavigationRepeatsRouteAsCommands() {
        var input = VimInputController()

        #expect(input.handleKeyDown("n", isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.searchNext))
        #expect(input.handleKeyDown("N", isRepeat: true, hasNavigableTextSelection: false, hasTextActionTarget: false) == .command(.searchPrevious))
    }
}

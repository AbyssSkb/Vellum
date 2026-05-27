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

        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false) == .handled)
        #expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false) == .command(.firstPage))
    }

    @Test
    func numericPrefixGCommandRoutesToPage() {
        var input = VimInputController()

        #expect(input.handleKeyDown("1", isRepeat: false, hasNavigableTextSelection: false) == .handled)
        #expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false) == .handled)
        #expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false) == .command(.jumpToPage(12)))
    }

    @Test
    func continuousKeyStartsRepeatsAndStops() {
        var input = VimInputController()

        #expect(input.handleKeyDown("j", isRepeat: false, hasNavigableTextSelection: false) == .continuousKey("j"))
        #expect(input.handleKeyDown("j", isRepeat: true, hasNavigableTextSelection: false) == .handled)
        #expect(input.handleKeyUp("j") == .stopContinuousKey)
        #expect(input.heldKey == nil)
    }

    @Test
    func copySelectionOnlyRoutesWhenSelectionIsNavigable() {
        var input = VimInputController()

        #expect(input.handleKeyDown("y", isRepeat: false, hasNavigableTextSelection: false) == .ignored)
        #expect(input.handleKeyDown("y", isRepeat: false, hasNavigableTextSelection: true) == .command(.copySelection))
    }

    @Test
    func searchCommandsRouteWithoutSelection() {
        var input = VimInputController()

        #expect(input.handleKeyDown("/", isRepeat: false, hasNavigableTextSelection: false) == .command(.beginSearch))
        #expect(input.handleKeyDown("n", isRepeat: false, hasNavigableTextSelection: false) == .command(.searchNext))
        #expect(input.handleKeyDown("N", isRepeat: false, hasNavigableTextSelection: false) == .command(.searchPrevious))
    }
}

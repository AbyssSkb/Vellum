import Testing
@testable import VellumCore

@Suite("Vim key map")
struct VimKeyMapTests {
    @Test
    func plusNormalizesToZoomInContinuousKey() {
        #expect(VimKeyMap.normalizedContinuousKey("+") == "=")
        #expect(VimKeyMap.isContinuousKey("+"))
        #expect(VimKeyMap.continuousCommand(for: "=") == .zoomIn)
    }

    @Test
    func uppercaseDAndUAreExtraLargeContinuousScrollKeys() {
        #expect(VimKeyMap.normalizedContinuousKey("D") == "D")
        #expect(VimKeyMap.normalizedContinuousKey("U") == "U")
        #expect(VimKeyMap.isContinuousKey("D"))
        #expect(VimKeyMap.isContinuousKey("U"))
        #expect(VimKeyMap.continuousCommand(for: "D") == .extraLargeScrollDown)
        #expect(VimKeyMap.continuousCommand(for: "U") == .extraLargeScrollUp)
    }

    @Test
    func wordMotionKeysDependOnNavigableSelection() {
        #expect(!VimKeyMap.isHandledKey("w", hasNavigableTextSelection: false, hasTextActionTarget: true))
        #expect(VimKeyMap.isHandledKey("w", hasNavigableTextSelection: true, hasTextActionTarget: true))
    }

    @Test
    func copyKeyDependsOnTextActionTarget() {
        #expect(!VimKeyMap.isHandledKey("y", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.isHandledKey("y", hasNavigableTextSelection: false, hasTextActionTarget: true))
        #expect(VimKeyMap.command(for: "y") == .copySelection)
    }

    @Test
    func searchKeysAreHandledWithoutSelection() {
        #expect(VimKeyMap.isHandledKey("/", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.isHandledKey("n", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.isHandledKey("N", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "/") == .beginSearch)
        #expect(VimKeyMap.command(for: "n") == .searchNext)
        #expect(VimKeyMap.command(for: "N") == .searchPrevious)
        #expect(VimKeyMap.repeatableCommand(for: "n") == .searchNext)
        #expect(VimKeyMap.repeatableCommand(for: "N") == .searchPrevious)
    }

    @Test
    func materializeSearchSelectionKeyIsHandledWithoutSelection() {
        #expect(VimKeyMap.isHandledKey("v", hasNavigableTextSelection: false, hasTextActionTarget: false))
        #expect(VimKeyMap.command(for: "v") == .materializeSearchSelection)
    }

    @Test
    func uppercaseFallbackLeavesDedicatedUppercaseCommandsAlone() {
        #expect(VimKeyMap.lowercaseFallback(for: "A") == "a")
        #expect(VimKeyMap.lowercaseFallback(for: "G") == nil)
        #expect(VimKeyMap.lowercaseFallback(for: "N") == "n")
    }
}

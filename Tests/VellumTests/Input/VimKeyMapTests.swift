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
    func wordMotionKeysDependOnNavigableSelection() {
        #expect(!VimKeyMap.isHandledKey("w", hasNavigableTextSelection: false))
        #expect(VimKeyMap.isHandledKey("w", hasNavigableTextSelection: true))
    }

    @Test
    func copyKeyDependsOnNavigableSelection() {
        #expect(!VimKeyMap.isHandledKey("y", hasNavigableTextSelection: false))
        #expect(VimKeyMap.isHandledKey("y", hasNavigableTextSelection: true))
        #expect(VimKeyMap.command(for: "y") == .copySelection)
    }

    @Test
    func searchKeysAreHandledWithoutSelection() {
        #expect(VimKeyMap.isHandledKey("/", hasNavigableTextSelection: false))
        #expect(VimKeyMap.isHandledKey("n", hasNavigableTextSelection: false))
        #expect(VimKeyMap.isHandledKey("N", hasNavigableTextSelection: false))
        #expect(VimKeyMap.command(for: "/") == .beginSearch)
        #expect(VimKeyMap.command(for: "n") == .searchNext)
        #expect(VimKeyMap.command(for: "N") == .searchPrevious)
    }

    @Test
    func uppercaseFallbackLeavesDedicatedUppercaseCommandsAlone() {
        #expect(VimKeyMap.lowercaseFallback(for: "A") == "a")
        #expect(VimKeyMap.lowercaseFallback(for: "G") == nil)
        #expect(VimKeyMap.lowercaseFallback(for: "N") == "n")
    }
}

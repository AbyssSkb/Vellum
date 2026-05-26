import Testing
@testable import Vellum

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
    func uppercaseFallbackLeavesDedicatedUppercaseCommandsAlone() {
        #expect(VimKeyMap.lowercaseFallback(for: "A") == "a")
        #expect(VimKeyMap.lowercaseFallback(for: "G") == nil)
    }
}

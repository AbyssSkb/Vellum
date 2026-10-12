import AppKit
import Testing
@testable import VellumCore

@Suite("AI explanation mouse trigger")
struct AIExplanationMouseTriggerTests {
    @Test(arguments: [
        (2, NSEvent.ModifierFlags(), false, true, true, true),
        (3, NSEvent.ModifierFlags(), false, true, true, false),
        (2, NSEvent.ModifierFlags(), false, true, false, false),
        (2, NSEvent.ModifierFlags(), false, false, true, false),
        (2, NSEvent.ModifierFlags.command, false, true, true, false),
        (2, NSEvent.ModifierFlags(), true, true, true, false)
    ])
    func explanationRequiresAnUnmodifiedMiddleClickOnAnInactiveSelection(
        buttonNumber: Int,
        modifierFlags: NSEvent.ModifierFlags,
        isAIInteractionActive: Bool,
        hasSelectedText: Bool,
        pointIsInsideSelection: Bool,
        expected: Bool
    ) {
        #expect(AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: buttonNumber,
            clickCount: 1,
            modifierFlags: modifierFlags,
            isAIInteractionActive: isAIInteractionActive,
            hasSelectedText: hasSelectedText,
            pointIsInsideSelection: pointIsInsideSelection
        ) == expected)
    }
}

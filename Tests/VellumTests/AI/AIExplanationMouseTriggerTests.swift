import AppKit
import Testing
@testable import VellumCore

@Suite("AI explanation mouse trigger")
struct AIExplanationMouseTriggerTests {
    @Test
    func middleMouseDownOnSelectionTriggersExplanation() {
        #expect(AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: AIExplanationMouseTrigger.middleButtonNumber,
            clickCount: 1,
            modifierFlags: [],
            isAIInteractionActive: false,
            hasSelectedText: true,
            pointIsInsideSelection: true
        ))
    }

    @Test
    func otherMouseButtonsDoNotTriggerExplanation() {
        #expect(!AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: 3,
            clickCount: 1,
            modifierFlags: [],
            isAIInteractionActive: false,
            hasSelectedText: true,
            pointIsInsideSelection: true
        ))
    }

    @Test
    func clicksOutsideSelectionDoNotTriggerExplanation() {
        #expect(!AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: AIExplanationMouseTrigger.middleButtonNumber,
            clickCount: 1,
            modifierFlags: [],
            isAIInteractionActive: false,
            hasSelectedText: true,
            pointIsInsideSelection: false
        ))
    }

    @Test
    func emptySelectionDoesNotTriggerExplanation() {
        #expect(!AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: AIExplanationMouseTrigger.middleButtonNumber,
            clickCount: 1,
            modifierFlags: [],
            isAIInteractionActive: false,
            hasSelectedText: false,
            pointIsInsideSelection: true
        ))
    }

    @Test
    func modifiedMiddleClicksDoNotTriggerExplanation() {
        #expect(!AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: AIExplanationMouseTrigger.middleButtonNumber,
            clickCount: 1,
            modifierFlags: [.command],
            isAIInteractionActive: false,
            hasSelectedText: true,
            pointIsInsideSelection: true
        ))
    }

    @Test
    func activeAIInteractionDoesNotStartAnotherExplanation() {
        #expect(!AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: .otherMouseDown,
            buttonNumber: AIExplanationMouseTrigger.middleButtonNumber,
            clickCount: 1,
            modifierFlags: [],
            isAIInteractionActive: true,
            hasSelectedText: true,
            pointIsInsideSelection: true
        ))
    }
}

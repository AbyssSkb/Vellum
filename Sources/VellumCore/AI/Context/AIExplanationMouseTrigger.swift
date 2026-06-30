import AppKit

enum AIExplanationMouseTrigger {
    static let middleButtonNumber = 2

    static func shouldExplainSelection(
        eventType: NSEvent.EventType,
        buttonNumber: Int,
        clickCount: Int,
        modifierFlags: NSEvent.ModifierFlags,
        isAIInteractionActive: Bool,
        hasSelectedText: Bool,
        pointIsInsideSelection: Bool
    ) -> Bool {
        guard eventType == .otherMouseDown,
              buttonNumber == middleButtonNumber,
              clickCount == 1,
              modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !isAIInteractionActive,
              hasSelectedText,
              pointIsInsideSelection else {
            return false
        }

        return true
    }
}

import AppKit
import Testing
@testable import VellumCore

@Suite("AI floating overlay presentation")
@MainActor
struct AIFloatingOverlayPresentationTests {
    @Test
    func updateFramesKeepsConversationOverlayAbovePDFSubviews() {
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let overlay = NSView(frame: NSRect(x: 10, y: 10, width: 120, height: 80))
        let coveringPDFSubview = NSView(frame: view.bounds)

        view.addSubview(overlay)
        view.addSubview(coveringPDFSubview)
        view.aiInteraction.conversationOverlay = overlay
        view.aiInteraction.activeConversationModel = AIConversationPopoverModel(context: Self.context())

        view.updateAIFloatingOverlayFrames()

        #expect(overlay.superview === view)
        #expect(view.subviews.last === overlay)
    }

    @Test
    func updateFramesReattachesDetachedConversationOverlay() {
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let overlay = NSView(frame: NSRect(x: 10, y: 10, width: 120, height: 80))

        view.aiInteraction.conversationOverlay = overlay
        view.aiInteraction.activeConversationModel = AIConversationPopoverModel(context: Self.context())

        view.updateAIFloatingOverlayFrames()

        #expect(overlay.superview === view)
        #expect(view.subviews.last === overlay)
    }

    private static func context() -> AIExplanationContext {
        AIExplanationContext(
            selectedText: "selected",
            currentParagraph: "selected paragraph",
            nearbyText: "nearby",
            fileName: "paper.pdf",
            directoryName: nil,
            outlineTitle: nil,
            pageNumbers: [1]
        )
    }
}

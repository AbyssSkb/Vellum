import AppKit
import Testing
@testable import VellumCore

@Suite("AI conversation popover model")
@MainActor
struct AIConversationPopoverModelTests {
    @Test
    func emptyPopoverHeightFollowsComposerTextHeight() {
        let model = AIConversationPopoverModel(context: Self.context())
        let measuredTextHeight = AIConversationPopoverMetrics.composerTextMinimumHeight + 42

        let didResize = model.updateComposerTextHeight(measuredTextHeight)

        #expect(didResize)
        #expect(model.composerTextHeight == ceil(measuredTextHeight))
        #expect(model.preferredHeight == model.composerHeight)
    }

    @Test
    func messageHeightRecalculatesWithDynamicComposerHeight() {
        let model = AIConversationPopoverModel(context: Self.context())
        model.messages = [
            AIConversationMessage(role: .user, content: "How should I read this?")
        ]

        _ = model.updateMessageContentHeight(120)
        #expect(model.preferredHeight == 120 + AIConversationPopoverMetrics.dividerHeight + model.composerHeight)

        _ = model.updateComposerTextHeight(92)
        #expect(model.preferredHeight == 120 + AIConversationPopoverMetrics.dividerHeight + model.composerHeight)
    }

    @Test
    func transcriptScrollRequestOnlyChangesWhenExplicitlyRequested() {
        let model = AIConversationPopoverModel(context: Self.context())
        let initialGeneration = model.transcriptScrollToBottomGeneration

        _ = model.updateComposerTextHeight(92)
        model.draft = "A longer prompt that resizes the composer."
        model.messages = [
            AIConversationMessage(role: .assistant, content: "Existing answer")
        ]
        #expect(model.transcriptScrollToBottomGeneration == initialGeneration)

        model.requestTranscriptScrollToBottom()
        #expect(model.transcriptScrollToBottomGeneration == initialGeneration + 1)
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

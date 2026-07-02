import Foundation
import Testing
@testable import VellumCore

@Suite("AI history")
struct AIHistoryTests {
    @Test
    func conversationSearchTextExcludesFileNameAndPages() {
        let item = AIConversationHistoryItem(
            id: UUID(),
            context: AIExplanationContext(
                selectedText: "selected phrase",
                currentParagraph: nil,
                nearbyText: "nearby text",
                fileName: "paper.pdf",
                directoryName: "Downloads",
                outlineTitle: nil,
                pageNumbers: [42]
            ),
            messages: [
                AIConversationMessage(role: .user, content: "question"),
                AIConversationMessage(role: .assistant, content: "answer")
            ],
            updatedAt: Date()
        )

        #expect(item.searchableText.contains("selected phrase"))
        #expect(item.searchableText.contains("answer"))
        #expect(!item.searchableText.contains("paper.pdf"))
        #expect(!item.searchableText.contains("42"))
    }

    @Test
    func explanationSearchTextExcludesFileNameAndPages() {
        let item = AIExplanationHistoryItem(
            id: UUID(),
            selectedText: "selected phrase",
            explanation: "saved explanation",
            fileName: "paper.pdf",
            documentKey: "/tmp/paper.pdf",
            pageNumbers: [42],
            updatedAt: Date()
        )

        #expect(item.searchableText.contains("selected phrase"))
        #expect(item.searchableText.contains("saved explanation"))
        #expect(!item.searchableText.contains("paper.pdf"))
        #expect(!item.searchableText.contains("42"))
    }
}

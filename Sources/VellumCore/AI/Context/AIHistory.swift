import Foundation

struct AIConversationHistoryItem: Identifiable {
    let id: UUID
    var context: AIExplanationContext
    var messages: [AIConversationMessage]
    var updatedAt: Date

    var selectedText: String {
        context.selectedText
    }

    var fileName: String {
        context.fileName
    }

    var pageNumbers: [Int] {
        context.pageNumbers
    }

    var searchableText: String {
        ([context.selectedText, context.outlineTitle] + messages.map(\.content))
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct AIExplanationHistoryItem: Identifiable {
    let id: UUID
    var selectedText: String
    var explanation: String
    var fileName: String
    var documentKey: String? = nil
    var pageNumbers: [Int]
    var updatedAt: Date

    var searchableText: String {
        [selectedText, explanation]
            .joined(separator: " ")
    }
}

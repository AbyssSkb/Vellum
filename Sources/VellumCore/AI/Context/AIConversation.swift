import Foundation

enum AIConversationRole: String, Sendable {
    case user
    case assistant
}

struct AIConversationMessage: Identifiable, Equatable, Sendable {
    var id = UUID()
    var role: AIConversationRole
    var content: String

    init(role: AIConversationRole, content: String) {
        self.role = role
        self.content = content
    }
}

enum AIConversationPromptRenderer {
    static func systemPrompt(context: AIExplanationContext) -> String {
        """
        You are Vellum's PDF reading assistant. The user selected text in a PDF and wants to discuss it.

        Answer the user's questions using the selected text and context window below. Keep answers focused on the selected passage. If the question needs information not present in the context, say what is missing instead of inventing details.

        PDF metadata:
        - File name: \(context.fileName)
        - Folder: \(context.directoryName ?? "Unknown")
        - Outline title: \(context.outlineTitle ?? "Unknown")
        - Pages: \(context.pageNumbers.map(String.init).joined(separator: ", "))

        Selected text:
        \(context.selectedText)

        Previous paragraph:
        \(context.previousParagraph ?? "Unavailable")

        Current paragraph:
        \(context.currentParagraph ?? "Unavailable")

        Next paragraph:
        \(context.nextParagraph ?? "Unavailable")

        Nearby extracted text:
        \(context.nearbyText)
        """
    }

    static func transcriptPrompt(
        context: AIExplanationContext,
        messages: [AIConversationMessage]
    ) -> String {
        let transcript = messages.map { message in
            let speaker = message.role == .user ? "User" : "Assistant"
            return "\(speaker):\n\(message.content)"
        }
        .joined(separator: "\n\n")

        return """
        \(systemPrompt(context: context))

        Conversation so far:
        \(transcript)

        Continue as Assistant. Return only the assistant's next message.
        """
    }
}

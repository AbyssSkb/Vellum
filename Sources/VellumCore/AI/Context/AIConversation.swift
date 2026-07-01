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
    static func systemPrompt(
        context: AIExplanationContext,
        configuration: AIPromptConfiguration = AIPromptSettings.current(profile: .conversation)
    ) -> String {
        AIPromptRenderer.renderUserPrompt(
            context: context,
            configuration: configuration
        )
    }

    static func transcriptPrompt(
        context: AIExplanationContext,
        messages: [AIConversationMessage],
        configuration: AIPromptConfiguration = AIPromptSettings.current(profile: .conversation)
    ) -> String {
        let transcript = messages.map { message in
            let speaker = message.role == .user ? "User" : "Assistant"
            return "\(speaker):\n\(message.content)"
        }
        .joined(separator: "\n\n")

        return """
        \(systemPrompt(context: context, configuration: configuration))

        Conversation so far:
        \(transcript)

        Continue as Assistant. Return only the assistant's next message.
        """
    }
}

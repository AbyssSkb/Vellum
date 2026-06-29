import Foundation

enum AIResponseParser {
    static func completionText(from data: Data, providerFormat: AIProviderFormat = .openAICompatible) throws -> String {
        switch providerFormat {
        case .openAICompatible:
            return try openAICompatibleCompletionText(from: data)
        case .anthropicMessages:
            return try anthropicMessageText(from: data)
        case .codexCLI:
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw AIExplanationError.emptyResponse }
            return text
        }
    }

    private static func openAICompatibleCompletionText(from data: Data) throws -> String {
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw AIExplanationError.emptyResponse
        }

        return text
    }

    private static func anthropicMessageText(from data: Data) throws -> String {
        let message = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        let text = message.content
            .filter { $0.type == "text" }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw AIExplanationError.emptyResponse
        }

        return text
    }

    static func modelIDs(from data: Data) throws -> [String] {
        let models = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return models.data
            .map(\.id)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private struct ChatCompletionResponse: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var message: ChatMessage
        }
    }

    private struct ModelListResponse: Decodable {
        var data: [Model]

        struct Model: Decodable {
            var id: String
        }
    }

    private struct AnthropicMessageResponse: Decodable {
        var content: [Content]

        struct Content: Decodable {
            var type: String
            var text: String
        }
    }
}

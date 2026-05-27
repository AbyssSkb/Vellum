import Foundation

enum AIResponseParser {
    static func completionText(from data: Data) throws -> String {
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
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
}

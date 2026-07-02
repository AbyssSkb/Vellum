import Foundation

enum AIStreamParser {
    enum Event: Equatable {
        case chunk(String)
        case chunkAndFinished(String, reason: String?)
        case finished(reason: String?)
        case done
        case ignored
    }

    static func event(from line: String) -> Event {
        guard line.hasPrefix("data:") else { return .ignored }

        let payload = line
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard payload != "[DONE]" else { return .done }
        guard let data = payload.data(using: .utf8) else { return .ignored }

        guard let chunk = try? JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data),
              let choice = chunk.choices.first else {
            return .ignored
        }

        let delta = choice.delta.content
        let finishReason = choice.finishReason

        if let delta, !delta.isEmpty, finishReason != nil {
            return .chunkAndFinished(delta, reason: finishReason)
        }

        if let delta, !delta.isEmpty {
            return .chunk(delta)
        }

        if finishReason != nil {
            return .finished(reason: finishReason)
        }

        return .ignored
    }

    private struct ChatCompletionStreamChunk: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var delta: Delta
            var finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Delta: Decodable {
            var content: String?
        }
    }
}

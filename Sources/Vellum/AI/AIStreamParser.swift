import Foundation

enum AIStreamParser {
    enum Event: Equatable {
        case chunk(String)
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
              let delta = chunk.choices.first?.delta.content,
              !delta.isEmpty else {
            return .ignored
        }

        return .chunk(delta)
    }

    private struct ChatCompletionStreamChunk: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var delta: Delta
        }

        struct Delta: Decodable {
            var content: String?
        }
    }
}

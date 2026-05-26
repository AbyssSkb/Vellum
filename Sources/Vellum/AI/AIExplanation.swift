import Foundation


enum AIExplanationClient {
    static func testConnection(configuration: AIConfiguration) async throws -> String {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(role: "user", content: "Ping")
            ],
            temperature: 0,
            maxTokens: 8,
            enableThinking: configuration.supportsSiliconFlowThinkingControls ? false : nil
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty != nil else {
            throw AIExplanationError.emptyResponse
        }

        return "模型可用：\(configuration.model)"
    }

    static func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        var request = URLRequest(url: configuration.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)

        let models = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return models.data
            .map(\.id)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: "你是 Vellum 的阅读助手，擅长解释 PDF 中被高亮的文字。你必须基于用户提供的原文和上下文回答，不要编造。若选中文本是单个英文单词或常见英文词形，附上音标；若选中文本本来是中文或无需翻译，省略中文翻译部分。"
                ),
                ChatMessage(role: "user", content: context.prompt)
            ],
            temperature: 0.2,
            maxTokens: 1200,
            enableThinking: configuration.supportsSiliconFlowThinkingControls ? false : nil
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw AIExplanationError.emptyResponse
        }

        return text
    }

    static func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: "你是 Vellum 的阅读助手。你必须基于用户提供的原文和上下文回答，重点解释用户选中文本本身，不要默认总结整段。若选中文本是单个英文单词或常见英文词形，附上音标；若选中文本本来是中文或无需翻译，省略中文翻译部分。"
                ),
                ChatMessage(role: "user", content: context.prompt)
            ],
            temperature: 0.2,
            maxTokens: 1200,
            stream: true,
            enableThinking: configuration.supportsSiliconFlowThinkingControls ? false : nil
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await bytes(for: request)
        try validate(response: response)

        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }

            let payload = line
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
                break
            }

            guard let chunk = try? JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta.content,
                  !delta.isEmpty else {
                continue
            }

            fullText += delta
            await MainActor.run {
                onChunk(delta)
            }
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIExplanationError.emptyResponse
        }

        return trimmed
    }

    private static func validate(data: Data, response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let message = serverErrorMessage(from: data, statusCode: httpResponse.statusCode)
            throw AIExplanationError.server(message)
        }
    }

    private static func validate(response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw AIExplanationError.server("AI 请求失败，HTTP \(httpResponse.statusCode)。")
        }
    }

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AIExplanationError.transport("AI 连接失败：\(error.localizedDescription)")
        }
    }

    private static func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await URLSession.shared.bytes(for: request)
        } catch {
            throw AIExplanationError.transport("AI 连接失败：\(error.localizedDescription)")
        }
    }

    private static func serverErrorMessage(from data: Data, statusCode: Int) -> String {
        let fallback = "AI 请求失败，HTTP \(statusCode)。"
        guard let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty else {
            return fallback
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "AI 请求失败，HTTP \(statusCode)：\(rawMessage)"
        }

        if let error = json["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.nilIfEmpty
            let type = (error["type"] as? String)?.nilIfEmpty
            let code = (error["code"] as? String)?.nilIfEmpty
            let param = (error["param"] as? String)?.nilIfEmpty
            let details = [
                type.map { "type=\($0)" },
                code.map { "code=\($0)" },
                param.map { "param=\($0)" }
            ].compactMap { $0 }.joined(separator: ", ")
            if let message, !details.isEmpty {
                return "AI 请求失败，HTTP \(statusCode)：\(message)（\(details)）"
            }
            if let message {
                return "AI 请求失败，HTTP \(statusCode)：\(message)"
            }
        }

        if let message = (json["message"] as? String)?.nilIfEmpty {
            return "AI 请求失败，HTTP \(statusCode)：\(message)"
        }

        return "AI 请求失败，HTTP \(statusCode)：\(rawMessage)"
    }

    private struct ChatCompletionRequest: Encodable {
        var model: String
        var messages: [ChatMessage]
        var temperature: Double
        var maxTokens: Int? = nil
        var stream: Bool? = nil
        var enableThinking: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case stream
            case enableThinking = "enable_thinking"
        }
    }

    private struct ChatMessage: Codable {
        var role: String
        var content: String
    }

    private struct ChatCompletionResponse: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var message: ChatMessage
        }
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

    private struct ModelListResponse: Decodable {
        var data: [Model]

        struct Model: Decodable {
            var id: String
        }
    }
}

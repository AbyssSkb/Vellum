import Foundation

enum AIRequestFactory {
    static func testConnectionRequest(configuration: AIConfiguration) throws -> URLRequest {
        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(role: "user", content: "Ping")
            ],
            temperature: 0,
            maxTokens: 8,
            enableThinking: configuration.supportsSiliconFlowThinkingControls ? false : nil
        )

        return try chatCompletionsRequest(
            configuration: configuration,
            timeout: 30,
            body: body
        )
    }

    static func modelsRequest(configuration: AIConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    static func explanationRequest(
        context: AIExplanationContext,
        configuration: AIConfiguration
    ) throws -> URLRequest {
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

        return try chatCompletionsRequest(
            configuration: configuration,
            timeout: 60,
            body: body
        )
    }

    static func streamingExplanationRequest(
        context: AIExplanationContext,
        configuration: AIConfiguration
    ) throws -> URLRequest {
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

        return try chatCompletionsRequest(
            configuration: configuration,
            timeout: 60,
            body: body
        )
    }

    private static func chatCompletionsRequest(
        configuration: AIConfiguration,
        timeout: TimeInterval,
        body: ChatCompletionRequest
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

struct ChatCompletionRequest: Encodable {
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

struct ChatMessage: Codable {
    var role: String
    var content: String
}

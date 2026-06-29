import Foundation

enum AIRequestFactory {
    static func functionTestRequest(configuration: AIConfiguration) throws -> URLRequest {
        switch configuration.providerFormat {
        case .openAICompatible:
            return try openAICompatibleFunctionTestRequest(configuration: configuration)
        case .anthropicMessages:
            return try anthropicFunctionTestRequest(configuration: configuration)
        case .codexCLI:
            throw AIExplanationError.server("Codex CLI 不使用 HTTP 请求。")
        }
    }

    static func connectionTestRequest(configuration: AIConfiguration) -> URLRequest {
        modelsRequest(configuration: configuration)
    }

    static func testConnectionRequest(configuration: AIConfiguration) throws -> URLRequest {
        try functionTestRequest(configuration: configuration)
    }

    private static func openAICompatibleFunctionTestRequest(configuration: AIConfiguration) throws -> URLRequest {
        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(role: "user", content: "Reply with OK.")
            ],
            temperature: 0,
            maxTokens: 64,
            enableThinking: configuration.supportsSiliconFlowThinkingControls ? false : nil
        )

        return try chatCompletionsRequest(
            configuration: configuration,
            timeout: 30,
            body: body
        )
    }

    private static func anthropicFunctionTestRequest(configuration: AIConfiguration) throws -> URLRequest {
        let body = AnthropicMessageRequest(
            model: configuration.model,
            messages: [
                ChatMessage(role: "user", content: "Reply with OK.")
            ],
            maxTokens: 64
        )

        return try anthropicRequest(
            configuration: configuration,
            timeout: 30,
            body: body
        )
    }

    static func modelsRequest(configuration: AIConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.modelsURL)
        request.httpMethod = "GET"
        applyAuthenticationHeaders(to: &request, configuration: configuration)
        request.timeoutInterval = 30
        return request
    }

    static func explanationRequest(
        context: AIExplanationContext,
        configuration: AIConfiguration
    ) throws -> URLRequest {
        if configuration.providerFormat == .anthropicMessages {
            return try anthropicExplanationRequest(
                context: context,
                configuration: configuration
            )
        }
        if configuration.providerFormat == .codexCLI {
            throw AIExplanationError.server("Codex CLI 不使用 HTTP 请求。")
        }

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
        if configuration.providerFormat == .anthropicMessages {
            return try anthropicExplanationRequest(
                context: context,
                configuration: configuration
            )
        }
        if configuration.providerFormat == .codexCLI {
            throw AIExplanationError.server("Codex CLI 不使用 HTTP 请求。")
        }

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
        applyAuthenticationHeaders(to: &request, configuration: configuration)
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func anthropicExplanationRequest(
        context: AIExplanationContext,
        configuration: AIConfiguration
    ) throws -> URLRequest {
        let body = AnthropicMessageRequest(
            model: configuration.model,
            system: "你是 Vellum 的阅读助手。你必须基于用户提供的原文和上下文回答，重点解释用户选中文本本身，不要默认总结整段。若选中文本是单个英文单词或常见英文词形，附上音标；若选中文本本来是中文或无需翻译，省略中文翻译部分。",
            messages: [
                ChatMessage(role: "user", content: context.prompt)
            ],
            maxTokens: 1200
        )

        return try anthropicRequest(
            configuration: configuration,
            timeout: 60,
            body: body
        )
    }

    private static func anthropicRequest(
        configuration: AIConfiguration,
        timeout: TimeInterval,
        body: AnthropicMessageRequest
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthenticationHeaders(to: &request, configuration: configuration)
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func applyAuthenticationHeaders(to request: inout URLRequest, configuration: AIConfiguration) {
        switch configuration.providerFormat {
        case .openAICompatible:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicMessages:
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .codexCLI:
            break
        }
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

struct AnthropicMessageRequest: Encodable {
    var model: String
    var system: String? = nil
    var messages: [ChatMessage]
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
    }
}

import Foundation


protocol AIExplaining: Sendable {
    func testConnection(configuration: AIConfiguration) async throws -> String
    func testFunction(configuration: AIConfiguration) async throws -> String
    func fetchModels(configuration: AIConfiguration) async throws -> [String]
    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String
    func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String
    func streamConversation(
        context: AIExplanationContext,
        messages: [AIConversationMessage],
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String
}

struct OpenAICompatibleAIExplanationClient: AIExplaining {
    func testConnection(configuration: AIConfiguration) async throws -> String {
        let request = AIRequestFactory.connectionTestRequest(configuration: configuration)
        let (data, response) = try await data(for: request, operation: "testConnection", configuration: configuration)
        try validate(data: data, response: response)

        let models = try AIResponseParser.modelIDs(from: data)
        return models.isEmpty ? "Endpoint responded. No models returned." : "Endpoint responded. \(models.count) models available."
    }

    func testFunction(configuration: AIConfiguration) async throws -> String {
        let request = try AIRequestFactory.functionTestRequest(configuration: configuration)
        let (data, response) = try await data(for: request, operation: "testFunction", configuration: configuration)
        try validate(data: data, response: response)

        do {
            let text = try AIResponseParser.completionText(from: data, providerFormat: configuration.providerFormat)
            return "Model responded: \(text)"
        } catch AIExplanationError.emptyResponse {
            return "Model responded, but returned empty text."
        }
    }

    func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        let request = AIRequestFactory.modelsRequest(configuration: configuration)
        let (data, response) = try await data(for: request, operation: "fetchModels", configuration: configuration)
        try validate(data: data, response: response)

        return try AIResponseParser.modelIDs(from: data)
    }

    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        let request = try AIRequestFactory.explanationRequest(
            context: context,
            configuration: configuration
        )
        let (data, response) = try await data(for: request, operation: "explain", configuration: configuration)
        try validate(data: data, response: response)
        return try AIResponseParser.completionText(from: data, providerFormat: configuration.providerFormat)
    }

    func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if configuration.providerFormat == .anthropicMessages {
            let explanation = try await explain(context: context, configuration: configuration)
            await MainActor.run {
                onChunk(explanation)
            }
            return explanation
        }

        let request = try AIRequestFactory.streamingExplanationRequest(
            context: context,
            configuration: configuration
        )
        let startedAt = Date()
        let (bytes, response) = try await bytes(
            for: request,
            operation: "streamExplanation",
            configuration: configuration,
            startedAt: startedAt
        )

        var fullText = ""
        do {
            try validate(response: response)

            streamLoop:
            for try await line in bytes.lines {
                switch AIStreamParser.event(from: line) {
                case .chunk(let delta):
                    fullText += delta
                    await MainActor.run {
                        onChunk(delta)
                    }
                case .done:
                    break streamLoop
                case .ignored:
                    continue
                }
            }

            let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AIExplanationError.emptyResponse
            }

            AIRequestLogger.recordHTTP(
                operation: "streamExplanation",
                configuration: configuration,
                request: request,
                response: response,
                startedAt: startedAt,
                responseText: trimmed
            )
            return trimmed
        } catch {
            AIRequestLogger.recordHTTP(
                operation: "streamExplanation",
                configuration: configuration,
                request: request,
                response: response,
                startedAt: startedAt,
                responseText: fullText,
                error: error
            )
            throw error
        }
    }

    func streamConversation(
        context: AIExplanationContext,
        messages: [AIConversationMessage],
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if configuration.providerFormat == .anthropicMessages {
            let request = try AIRequestFactory.conversationRequest(
                context: context,
                messages: messages,
                configuration: configuration
            )
            let (data, response) = try await data(for: request, operation: "conversation", configuration: configuration)
            try validate(data: data, response: response)
            let text = try AIResponseParser.completionText(from: data, providerFormat: configuration.providerFormat)
            await MainActor.run {
                onChunk(text)
            }
            return text
        }

        let request = try AIRequestFactory.streamingConversationRequest(
            context: context,
            messages: messages,
            configuration: configuration
        )
        let startedAt = Date()
        let (bytes, response) = try await bytes(
            for: request,
            operation: "streamConversation",
            configuration: configuration,
            startedAt: startedAt
        )

        var fullText = ""
        do {
            try validate(response: response)

            streamLoop:
            for try await line in bytes.lines {
                switch AIStreamParser.event(from: line) {
                case .chunk(let delta):
                    fullText += delta
                    await MainActor.run {
                        onChunk(delta)
                    }
                case .done:
                    break streamLoop
                case .ignored:
                    continue
                }
            }

            let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AIExplanationError.emptyResponse
            }

            AIRequestLogger.recordHTTP(
                operation: "streamConversation",
                configuration: configuration,
                request: request,
                response: response,
                startedAt: startedAt,
                responseText: trimmed
            )
            return trimmed
        } catch {
            AIRequestLogger.recordHTTP(
                operation: "streamConversation",
                configuration: configuration,
                request: request,
                response: response,
                startedAt: startedAt,
                responseText: fullText,
                error: error
            )
            throw error
        }
    }

    private func validate(data: Data, response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let message = AIHTTPErrorMessage.message(from: data, statusCode: httpResponse.statusCode)
            throw AIExplanationError.server(message)
        }
    }

    private func validate(response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw AIExplanationError.server("AI 请求失败，HTTP \(httpResponse.statusCode)。")
        }
    }

    private func data(
        for request: URLRequest,
        operation: String,
        configuration: AIConfiguration
    ) async throws -> (Data, URLResponse) {
        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            AIRequestLogger.recordHTTP(
                operation: operation,
                configuration: configuration,
                request: request,
                response: response,
                startedAt: startedAt,
                responseData: data
            )
            return (data, response)
        } catch {
            AIRequestLogger.recordHTTP(
                operation: operation,
                configuration: configuration,
                request: request,
                response: nil,
                startedAt: startedAt,
                error: error
            )
            throw AIExplanationError.transport("AI 连接失败：\(error.localizedDescription)")
        }
    }

    private func bytes(
        for request: URLRequest,
        operation: String,
        configuration: AIConfiguration,
        startedAt: Date
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await URLSession.shared.bytes(for: request)
        } catch {
            AIRequestLogger.recordHTTP(
                operation: operation,
                configuration: configuration,
                request: request,
                response: nil,
                startedAt: startedAt,
                error: error
            )
            throw AIExplanationError.transport("AI 连接失败：\(error.localizedDescription)")
        }
    }
}

enum AIExplanationClient {
    private static let httpClient: any AIExplaining = OpenAICompatibleAIExplanationClient()
    private static let codexClient: any AIExplaining = CodexAppServerAIExplanationClient()

    static func testConnection(configuration: AIConfiguration) async throws -> String {
        try await client(for: configuration).testConnection(configuration: configuration)
    }

    static func testFunction(configuration: AIConfiguration) async throws -> String {
        try await client(for: configuration).testFunction(configuration: configuration)
    }

    static func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        try await client(for: configuration).fetchModels(configuration: configuration)
    }

    static func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        try await client(for: configuration).explain(context: context, configuration: configuration)
    }

    static func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await client(for: configuration).streamExplanation(
            context: context,
            configuration: configuration,
            onChunk: onChunk
        )
    }

    static func streamConversation(
        context: AIExplanationContext,
        messages: [AIConversationMessage],
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await client(for: configuration).streamConversation(
            context: context,
            messages: messages,
            configuration: configuration,
            onChunk: onChunk
        )
    }

    private static func client(for configuration: AIConfiguration) -> any AIExplaining {
        switch configuration.providerFormat {
        case .openAICompatible, .anthropicMessages:
            return httpClient
        case .codexCLI:
            return codexClient
        }
    }
}

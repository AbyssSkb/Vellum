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
}

struct OpenAICompatibleAIExplanationClient: AIExplaining {
    func testConnection(configuration: AIConfiguration) async throws -> String {
        let request = AIRequestFactory.connectionTestRequest(configuration: configuration)
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)

        let models = try AIResponseParser.modelIDs(from: data)
        return models.isEmpty ? "Endpoint responded. No models returned." : "Endpoint responded. \(models.count) models available."
    }

    func testFunction(configuration: AIConfiguration) async throws -> String {
        let request = try AIRequestFactory.functionTestRequest(configuration: configuration)
        let (data, response) = try await data(for: request)
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
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)

        return try AIResponseParser.modelIDs(from: data)
    }

    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        let request = try AIRequestFactory.explanationRequest(
            context: context,
            configuration: configuration
        )
        let (data, response) = try await data(for: request)
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
        let (bytes, response) = try await bytes(for: request)
        try validate(response: response)

        var fullText = ""
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

        return trimmed
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

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AIExplanationError.transport("AI 连接失败：\(error.localizedDescription)")
        }
    }

    private func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await URLSession.shared.bytes(for: request)
        } catch {
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

    private static func client(for configuration: AIConfiguration) -> any AIExplaining {
        switch configuration.providerFormat {
        case .openAICompatible, .anthropicMessages:
            return httpClient
        case .codexCLI:
            return codexClient
        }
    }
}

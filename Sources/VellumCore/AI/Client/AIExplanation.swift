import Foundation


protocol AIExplaining: Sendable {
    func testConnection(configuration: AIConfiguration) async throws -> String
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
        let request = try AIRequestFactory.testConnectionRequest(configuration: configuration)
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)

        _ = try AIResponseParser.completionText(from: data)
        return "模型可用：\(configuration.model)"
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
        return try AIResponseParser.completionText(from: data)
    }

    func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
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
    static let shared: any AIExplaining = OpenAICompatibleAIExplanationClient()

    static func testConnection(configuration: AIConfiguration) async throws -> String {
        try await shared.testConnection(configuration: configuration)
    }

    static func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        try await shared.fetchModels(configuration: configuration)
    }

    static func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        try await shared.explain(context: context, configuration: configuration)
    }

    static func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await shared.streamExplanation(
            context: context,
            configuration: configuration,
            onChunk: onChunk
        )
    }
}

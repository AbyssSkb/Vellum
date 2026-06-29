import Foundation
import Testing
@testable import VellumCore

@Suite("AI request factory")
struct AIRequestFactoryTests {
    @Test
    func currentConfigurationReadsSelectedProviderSettings() throws {
        let defaults = UserDefaults.standard
        let providerID = "anthropic"
        let keys = [
            AISettingsKeys.providerID,
            AISettingsKeys.baseURL,
            AISettingsKeys.model,
            AISettingsKeys.apiKey,
            AISettingsKeys.baseURLKey(for: providerID),
            AISettingsKeys.modelKey(for: providerID),
            AISettingsKeys.apiKeyKey(for: providerID)
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            keys.forEach { defaults.removeObject(forKey: $0) }
        }

        defaults.set(providerID, forKey: AISettingsKeys.providerID)
        defaults.set("https://legacy.example.com/v1", forKey: AISettingsKeys.baseURL)
        defaults.set("legacy-model", forKey: AISettingsKeys.model)
        defaults.set("legacy-key", forKey: AISettingsKeys.apiKey)
        defaults.set("https://api.anthropic.com/v1", forKey: AISettingsKeys.baseURLKey(for: providerID))
        defaults.set("claude-test", forKey: AISettingsKeys.modelKey(for: providerID))
        defaults.set("anthropic-key", forKey: AISettingsKeys.apiKeyKey(for: providerID))

        let configuration = try AIConfiguration.current()

        #expect(configuration.baseURL.absoluteString == "https://api.anthropic.com/v1")
        #expect(configuration.model == "claude-test")
        #expect(configuration.apiKey == "anthropic-key")
        #expect(configuration.providerFormat == .anthropicMessages)
    }

    @Test
    func codexCLIConfigurationUsesExecutablePathAndAllowsEmptySecrets() throws {
        let configuration = try AIConfiguration(
            baseURLString: "/opt/homebrew/bin/codex",
            model: "",
            apiKey: "",
            providerFormat: .codexCLI,
            requireModel: true
        )

        #expect(configuration.providerFormat == .codexCLI)
        #expect(configuration.codexExecutablePath == "/opt/homebrew/bin/codex")
        #expect(configuration.model == "")
        #expect(configuration.codexProfile == "")
    }

    @Test
    func codexCLIProviderPresetIsAvailable() {
        let preset = AIProviderPreset.preset(for: "codex-cli")

        #expect(preset.name == "Codex")
        #expect(preset.format == .codexCLI)
        #expect(!preset.baseURL.isEmpty)
    }

    @Test
    func modelsRequestUsesModelsEndpointAndAuthorization() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "test-model",
            apiKey: "secret"
        )

        let request = AIRequestFactory.modelsRequest(configuration: configuration)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/models")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.timeoutInterval == 30)
        #expect(request.httpBody == nil)
    }

    @Test
    func anthropicModelsRequestUsesMessagesAuthentication() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.anthropic.com/v1",
            model: "claude-3-5-haiku-latest",
            apiKey: "secret",
            providerFormat: .anthropicMessages
        )

        let request = AIRequestFactory.modelsRequest(configuration: configuration)

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func testConnectionRequestBuildsCompactChatCompletionBody() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "test-model",
            apiKey: "secret"
        )

        let request = try AIRequestFactory.testConnectionRequest(configuration: configuration)
        let body = try requestBody(request)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.timeoutInterval == 30)
        #expect(body["model"] as? String == "test-model")
        #expect(body["temperature"] as? Double == 0)
        #expect(body["max_tokens"] as? Int == 64)
        #expect(body["stream"] == nil)
    }

    @Test
    func anthropicFunctionTestUsesMessagesEndpoint() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.anthropic.com/v1",
            model: "claude-3-5-haiku-latest",
            apiKey: "secret",
            providerFormat: .anthropicMessages
        )

        let request = try AIRequestFactory.functionTestRequest(configuration: configuration)
        let body = try requestBody(request)
        let messages = try #require(body["messages"] as? [[String: String]])

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(body["model"] as? String == "claude-3-5-haiku-latest")
        #expect(body["max_tokens"] as? Int == 64)
        #expect(messages.first?["content"] == "Reply with OK.")
    }

    @Test
    func streamingExplanationRequestEnablesStream() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "test-model",
            apiKey: "secret"
        )
        let context = makeContext()

        let request = try AIRequestFactory.streamingExplanationRequest(
            context: context,
            configuration: configuration
        )
        let body = try requestBody(request)
        let messages = try #require(body["messages"] as? [[String: String]])

        #expect(request.timeoutInterval == 60)
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == 1200)
        #expect(messages.last?["role"] == "user")
        #expect(messages.last?["content"] == context.prompt)
    }

    @Test
    func siliconFlowRequestsDisableThinking() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.siliconflow.cn/v1",
            model: "test-model",
            apiKey: "secret"
        )
        let context = makeContext()

        let request = try AIRequestFactory.explanationRequest(
            context: context,
            configuration: configuration
        )
        let body = try requestBody(request)

        #expect(body["enable_thinking"] as? Bool == false)
    }

    @Test
    func anthropicExplanationUsesSystemAndUserMessages() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.anthropic.com/v1",
            model: "claude-3-5-haiku-latest",
            apiKey: "secret",
            providerFormat: .anthropicMessages
        )
        let context = makeContext()

        let request = try AIRequestFactory.explanationRequest(
            context: context,
            configuration: configuration
        )
        let body = try requestBody(request)
        let messages = try #require(body["messages"] as? [[String: String]])

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(body["system"] as? String != nil)
        #expect(body["max_tokens"] as? Int == 1200)
        #expect(messages.last?["role"] == "user")
        #expect(messages.last?["content"] == context.prompt)
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeContext() -> AIExplanationContext {
        AIExplanationContext(
            selectedText: "term",
            currentParagraph: "A paragraph with term in context.",
            nearbyText: "Nearby context",
            fileName: "paper.pdf",
            pageNumbers: [3]
        )
    }
}

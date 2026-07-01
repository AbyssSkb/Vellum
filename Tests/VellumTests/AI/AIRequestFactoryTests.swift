import Foundation
import Testing
@testable import VellumCore

@Suite("AI request factory")
struct AIRequestFactoryTests {
    @Test
    func currentConfigurationReadsSelectedProviderSettings() throws {
        let defaults = try isolatedDefaults(named: "currentConfigurationReadsSelectedProviderSettings")
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

        let configuration = try AIConfiguration.current(defaults: defaults)

        #expect(configuration.baseURL.absoluteString == "https://api.anthropic.com/v1")
        #expect(configuration.model == "claude-test")
        #expect(configuration.apiKey == "anthropic-key")
        #expect(configuration.providerFormat == .anthropicMessages)
    }

    @Test
    func conversationConfigurationIsIndependentFromExplanationSettings() throws {
        let defaults = try isolatedDefaults(named: "conversationConfigurationIsIndependentFromExplanationSettings")
        let keys = [
            AISettingsKeys.providerID,
            AISettingsKeys.conversationProviderID,
            AISettingsKeys.baseURLKey(for: "openai"),
            AISettingsKeys.modelKey(for: "openai"),
            AISettingsKeys.apiKeyKey(for: "openai"),
            AISettingsKeys.conversationBaseURLKey(for: "anthropic"),
            AISettingsKeys.conversationModelKey(for: "anthropic"),
            AISettingsKeys.conversationAPIKeyKey(for: "anthropic")
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            keys.forEach { defaults.removeObject(forKey: $0) }
        }

        defaults.set("openai", forKey: AISettingsKeys.providerID)
        defaults.set("https://api.explain.example/v1", forKey: AISettingsKeys.baseURLKey(for: "openai"))
        defaults.set("explain-model", forKey: AISettingsKeys.modelKey(for: "openai"))
        defaults.set("explain-key", forKey: AISettingsKeys.apiKeyKey(for: "openai"))
        defaults.set("anthropic", forKey: AISettingsKeys.conversationProviderID)
        defaults.set("https://api.anthropic.com/v1", forKey: AISettingsKeys.conversationBaseURLKey(for: "anthropic"))
        defaults.set("chat-model", forKey: AISettingsKeys.conversationModelKey(for: "anthropic"))
        defaults.set("chat-key", forKey: AISettingsKeys.conversationAPIKeyKey(for: "anthropic"))

        let explanation = try AIConfiguration.current(profile: .explanation, defaults: defaults)
        let conversation = try AIConfiguration.current(profile: .conversation, defaults: defaults)

        #expect(explanation.model == "explain-model")
        #expect(explanation.apiKey == "explain-key")
        #expect(explanation.providerFormat == .openAICompatible)
        #expect(conversation.model == "chat-model")
        #expect(conversation.apiKey == "chat-key")
        #expect(conversation.providerFormat == .anthropicMessages)
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
    func siliconFlowProviderPresetIsAvailable() {
        let preset = AIProviderPreset.preset(for: "siliconflow")

        #expect(preset.name == "SiliconFlow")
        #expect(preset.baseURL == "https://api.siliconflow.cn/v1")
        #expect(preset.defaultModel == "deepseek-ai/DeepSeek-V3")
        #expect(preset.format == .openAICompatible)
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
            configuration: configuration,
            promptConfiguration: .default
        )
        let body = try requestBody(request)
        let messages = try #require(body["messages"] as? [[String: String]])
        let renderedPrompt = AIPromptRenderer.render(context: context, configuration: .default)

        #expect(request.timeoutInterval == 60)
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == 1200)
        #expect(messages.first?["role"] == "system")
        #expect(messages.first?["content"] == renderedPrompt.system)
        #expect(messages.last?["role"] == "user")
        #expect(messages.last?["content"] == renderedPrompt.user)
    }

    @Test
    func streamingConversationRequestIncludesContextAndMessages() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "chat-model",
            apiKey: "secret"
        )
        let context = makeContext()
        let messages = [
            AIConversationMessage(role: .user, content: "Why does this matter?"),
            AIConversationMessage(role: .assistant, content: "It frames the claim."),
            AIConversationMessage(role: .user, content: "Give me a shorter version.")
        ]

        let request = try AIRequestFactory.streamingConversationRequest(
            context: context,
            messages: messages,
            configuration: configuration
        )
        let body = try requestBody(request)
        let requestMessages = try #require(body["messages"] as? [[String: String]])

        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.timeoutInterval == 90)
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == 1600)
        #expect(requestMessages.first?["role"] == "system")
        #expect(requestMessages.first?["content"]?.contains("Selected text:\nterm") == true)
        #expect(requestMessages.dropFirst().map { $0["role"] } == ["user", "assistant", "user"])
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
            configuration: configuration,
            promptConfiguration: .default
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
            configuration: configuration,
            promptConfiguration: .default
        )
        let body = try requestBody(request)
        let messages = try #require(body["messages"] as? [[String: String]])
        let renderedPrompt = AIPromptRenderer.render(context: context, configuration: .default)

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(body["system"] as? String == renderedPrompt.system)
        #expect(body["max_tokens"] as? Int == 1200)
        #expect(messages.last?["role"] == "user")
        #expect(messages.last?["content"] == renderedPrompt.user)
    }

    @Test
    func explanationRequestUsesCustomPromptConfiguration() throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "test-model",
            apiKey: "secret"
        )
        let context = makeContext()
        let promptConfiguration = AIPromptConfiguration(
            targetLanguage: "Spanish",
            template: "Explain {{selectedText}} in {{targetLanguage}} from {{fileName}}."
        )

        let request = try AIRequestFactory.explanationRequest(
            context: context,
            configuration: configuration,
            promptConfiguration: promptConfiguration
        )
        let body = try requestBody(request)
        let messages = try #require(body["messages"] as? [[String: String]])

        #expect(messages.last?["content"] == "Explain term in Spanish from paper.pdf.")
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func isolatedDefaults(named name: String) throws -> UserDefaults {
        let suiteName = "VellumTests.\(name).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

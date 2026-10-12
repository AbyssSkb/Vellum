import Foundation
import Testing
@testable import VellumCore

@Suite("AI request factory")
struct AIRequestFactoryTests {
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

    @Test(arguments: ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-2025-08-07", "o1", "o1-mini", "o1-preview", "o3", "o3-mini", "o4-mini-2025-04-16"])
    func reasoningModelsUseSupportedFunctionTestParameters(model: String) throws {
        let configuration = try AIConfiguration(baseURLString: "https://api.openai.com/v1", model: model, apiKey: "test-key")
        let body = try requestBody(AIRequestFactory.functionTestRequest(configuration: configuration))

        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] == nil)
        #expect(body["max_completion_tokens"] as? Int == 64)

        let explanation = try requestBody(AIRequestFactory.streamingExplanationRequest(context: makeContext(), configuration: configuration))
        let conversation = try requestBody(AIRequestFactory.streamingConversationRequest(context: makeContext(), messages: [], configuration: configuration))
        #expect(explanation["temperature"] == nil)
        #expect(conversation["temperature"] == nil)
    }

    @Test(arguments: ["gpt-4.1-mini", "gpt-5-chat-latest", "gpt-5.1-chat-latest", "deepseek-chat"])
    func nonReasoningModelsRetainTemperature(model: String) throws {
        let configuration = try AIConfiguration(baseURLString: "https://api.example.com/v1", model: model, apiKey: "test-key")
        let body = try requestBody(AIRequestFactory.functionTestRequest(configuration: configuration))

        #expect(body["temperature"] as? Double == 0)
        #expect(body["max_tokens"] as? Int == 64)
        #expect(body["max_completion_tokens"] == nil)
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
        #expect(body["max_tokens"] == nil)
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
        #expect(body["max_tokens"] == nil)
        #expect(requestMessages.first?["role"] == "system")
        #expect(requestMessages.first?["content"]?.contains("<selected_text>\nterm\n</selected_text>") == true)
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

    @Test(arguments: [AIProviderFormat.openAICompatible, .anthropicMessages])
    func streamingRequestsPreserveProviderBodies(provider: AIProviderFormat) throws {
        let configuration = try AIConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "test-model",
            apiKey: "secret",
            providerFormat: provider
        )
        let context = makeContext()
        let messages = [AIConversationMessage(role: .user, content: "Explain the result.")]
        let requests = [
            (
                try AIRequestFactory.explanationRequest(context: context, configuration: configuration, promptConfiguration: .default),
                try AIRequestFactory.streamingExplanationRequest(context: context, configuration: configuration, promptConfiguration: .default)
            ),
            (
                try AIRequestFactory.conversationRequest(context: context, messages: messages, configuration: configuration, promptConfiguration: .default),
                try AIRequestFactory.streamingConversationRequest(context: context, messages: messages, configuration: configuration, promptConfiguration: .default)
            )
        ]

        for (plain, streaming) in requests {
            let plainBody = try requestBody(plain)
            var streamingBody = try requestBody(streaming)
            #expect(plainBody["stream"] == nil)
            #expect(streamingBody.removeValue(forKey: "stream") as? Bool == (provider == .openAICompatible ? true : nil))
            #expect(NSDictionary(dictionary: plainBody) == NSDictionary(dictionary: streamingBody))
            #expect(plain.url == streaming.url)
            #expect(plain.timeoutInterval == streaming.timeoutInterval)
            #expect(plain.allHTTPHeaderFields == streaming.allHTTPHeaderFields)
        }
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

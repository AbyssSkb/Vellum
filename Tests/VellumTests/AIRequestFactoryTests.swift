import Foundation
import Testing
@testable import Vellum

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
        #expect(body["max_tokens"] as? Int == 8)
        #expect(body["stream"] == nil)
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

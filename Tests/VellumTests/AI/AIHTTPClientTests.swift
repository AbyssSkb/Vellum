import Foundation
import Testing
@testable import VellumCore

@Suite("AI HTTP client")
@MainActor
struct AIHTTPClientTests {
    @Test(arguments: ["completion", "anthropic"])
    func modelValidationReturnsAStatusInsteadOfTheGeneratedText(fixture: String) async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let result = try await OpenAICompatibleAIExplanationClient(session: session)
            .testFunction(configuration: makeConfiguration(fixture: fixture))

        #expect(result == AppUILanguage.saved().text(.aiModelResponded))
    }

    @Test(arguments: [false, true], ["done", "finished", "anthropic"])
    func bothEntryPointsCompleteAndPublishChunks(conversation: Bool, fixture: String) async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let configuration = try makeConfiguration(fixture: fixture)
        var chunks: [String] = []

        let result = try await stream(
            client: OpenAICompatibleAIExplanationClient(session: session),
            configuration: configuration,
            conversation: conversation
        ) { chunk in
            MainActor.assertIsolated()
            chunks.append(chunk)
        }

        #expect(result == "Hello world")
        #expect(chunks == (fixture == "anthropic" ? ["Hello world"] : [" Hello", " world "]))
    }

    @Test(arguments: [false, true], ["truncated", "unfinished", "provider-error", "http-error", "cancelled"])
    func bothEntryPointsRejectFailedStreams(conversation: Bool, fixture: String) async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        var chunks: [String] = []

        do {
            _ = try await stream(
                client: OpenAICompatibleAIExplanationClient(session: session),
                configuration: makeConfiguration(fixture: fixture),
                conversation: conversation
            ) { chunks.append($0) }
            Issue.record("Expected \(fixture) to fail")
        } catch let error as AIExplanationError {
            switch (fixture, error) {
            case ("truncated", .responseTruncated), ("unfinished", .streamEndedPrematurely):
                #expect(chunks == ["partial"])
            case ("provider-error", .server(let message)):
                #expect(message.contains("Quota exhausted"))
                #expect(message.contains("code=quota"))
                #expect(chunks.isEmpty)
            case ("http-error", .server(let message)):
                #expect(message.contains("503"))
                #expect(chunks.isEmpty)
            case ("cancelled", .transport(let message)):
                #expect(!message.isEmpty)
                #expect(chunks.isEmpty)
            default:
                Issue.record("Unexpected \(error) for \(fixture)")
            }
        }
    }

    private func stream(
        client: OpenAICompatibleAIExplanationClient,
        configuration: AIConfiguration,
        conversation: Bool,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let context = AIExplanationContext(
            selectedText: "term",
            currentParagraph: "A term in context.",
            nearbyText: "Nearby context",
            fileName: "paper.pdf",
            pageNumbers: [1]
        )
        if conversation {
            return try await client.streamConversation(
                context: context,
                messages: [AIConversationMessage(role: .user, content: "Explain this.")],
                configuration: configuration,
                onChunk: onChunk
            )
        }
        return try await client.streamExplanation(context: context, configuration: configuration, onChunk: onChunk)
    }

    private func makeConfiguration(fixture: String) throws -> AIConfiguration {
        try AIConfiguration(
            baseURLString: "https://\(fixture).test/v1",
            model: "test-model",
            apiKey: "secret",
            providerFormat: fixture == "anthropic" ? .anthropicMessages : .openAICompatible
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIHTTPStubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AIHTTPStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let fixture = url.host!.components(separatedBy: ".").first!
        if fixture == "cancelled" {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }

        let body: String
        switch fixture {
        case "completion":
            body = #"{"choices":[{"message":{"role":"assistant","content":"A complete model response that should not be repeated in a transient notification."}}]}"#
        case "anthropic":
            body = #"{"content":[{"type":"text","text":"Hello world"}]}"#
        case "provider-error":
            body = #"data: {"error":{"message":"Quota exhausted","code":"quota"}}"# + "\n\n"
        case "http-error":
            body = #"{"error":{"message":"Unavailable"}}"#
        case "truncated", "unfinished":
            body = #"data: {"choices":[{"delta":{"content":"partial"}}]}"# + "\n\n"
                + (fixture == "truncated" ? #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"# + "\n\ndata: [DONE]\n\n" : "")
        default:
            body = #"data: {"choices":[{"delta":{"content":" Hello"}}]}"# + "\n\n"
                + #"data: {"choices":[{"delta":{"content":" world "},"finish_reason":"stop"}]}"# + "\n\n"
                + (fixture == "done" ? "data: [DONE]\n\n" + #"data: {"choices":[{"delta":{"content":"ignored"}}]}"# + "\n\n" : "")
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: fixture == "http-error" ? 503 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": fixture == "anthropic" ? "application/json" : "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

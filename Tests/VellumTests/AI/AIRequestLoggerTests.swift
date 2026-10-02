import Foundation
import Testing
@testable import VellumCore

@Suite("AI request logger")
struct AIRequestLoggerTests {
    @Test
    func sanitizedHeadersRedactSecrets() {
        let headers = AIRequestLogger.sanitizedHeaders([
            "Authorization": "Bearer secret",
            "x-api-key": "secret-key",
            "Content-Type": "application/json"
        ])

        #expect(headers["Authorization"] == "<redacted>")
        #expect(headers["x-api-key"] == "<redacted>")
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test
    func sanitizedURLRedactsCredentialsAndAllQueryValues() throws {
        let url = try #require(URL(string: "https://us%65r:p%40ss@example.test:8443/v1/chat%20completions?api_key=secret&mode=debug&api_key=sec%72et%26nested%3Dvalue&empty=&flag"))

        let sanitized = try #require(AIRequestLogger.sanitizedURL(url))
        let components = try #require(URLComponents(string: sanitized))

        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.host == "example.test")
        #expect(components.port == 8443)
        #expect(components.percentEncodedPath == "/v1/chat%20completions")
        #expect(components.queryItems == [
            URLQueryItem(name: "api_key", value: "<redacted>"),
            URLQueryItem(name: "mode", value: "<redacted>"),
            URLQueryItem(name: "api_key", value: "<redacted>"),
            URLQueryItem(name: "empty", value: "<redacted>"),
            URLQueryItem(name: "flag", value: nil)
        ])
    }

    @Test
    func sanitizedURLPreservesPlainURLsAndMissingURL() throws {
        let url = try #require(URL(string: "https://example.test/v1/models"))

        #expect(AIRequestLogger.sanitizedURL(url) == url.absoluteString)
        #expect(AIRequestLogger.sanitizedURL(nil) == nil)
    }

    @Test
    func textPreviewPrettyPrintsJSON() throws {
        let data = Data(#"{"model":"test","messages":[{"role":"user","content":"hello"}]}"#.utf8)

        let preview = try #require(AIRequestLogger.textPreview(from: data, maxCharacters: 200))

        #expect(preview.contains("\"model\" : \"test\""))
        #expect(preview.contains("\"messages\" : ["))
    }

    @Test
    func textPreviewLimitsLength() throws {
        let data = Data(#"{"model":"test","messages":[{"role":"user","content":"hello"}]}"#.utf8)

        let preview = try #require(AIRequestLogger.textPreview(from: data, maxCharacters: 40))

        #expect(preview.contains("<truncated"))
    }
}

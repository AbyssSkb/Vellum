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

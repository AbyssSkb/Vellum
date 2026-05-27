import Foundation
import Testing
@testable import VellumCore

@Suite("AI HTTP error message")
struct AIHTTPErrorMessageTests {
    @Test
    func emptyBodyUsesStatusFallback() {
        #expect(AIHTTPErrorMessage.message(from: Data(), statusCode: 500) == "AI 请求失败，HTTP 500。")
    }

    @Test
    func plainTextBodyIsIncluded() {
        let data = Data("Service unavailable".utf8)

        #expect(AIHTTPErrorMessage.message(from: data, statusCode: 503) == "AI 请求失败，HTTP 503：Service unavailable")
    }

    @Test
    func openAIStyleErrorIncludesDetails() {
        let data = Data("""
        {
          "error": {
            "message": "Invalid API key",
            "type": "auth_error",
            "code": "invalid_api_key",
            "param": "Authorization"
          }
        }
        """.utf8)

        #expect(AIHTTPErrorMessage.message(from: data, statusCode: 401) == "AI 请求失败，HTTP 401：Invalid API key（type=auth_error, code=invalid_api_key, param=Authorization）")
    }

    @Test
    func topLevelMessageIsUsedWhenPresent() {
        let data = Data(#"{"message":"Rate limited"}"#.utf8)

        #expect(AIHTTPErrorMessage.message(from: data, statusCode: 429) == "AI 请求失败，HTTP 429：Rate limited")
    }
}

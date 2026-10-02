import Foundation
import Testing
@testable import VellumCore

@Suite("AI HTTP error message")
struct AIHTTPErrorMessageTests {
    @Test
    func englishHTTPAndStreamErrorsPreserveProviderDetails() {
        let data = Data(#"{"error":{"message":"Invalid API key","code":"invalid_api_key"}}"#.utf8)
        #expect(AIHTTPErrorMessage.message(from: Data(), statusCode: 500, language: .english) == "AI request failed, HTTP 500.")
        #expect(AIHTTPErrorMessage.message(from: data, statusCode: nil, language: .english) == "AI request failed: Invalid API key (code=invalid_api_key)")
        #expect(AIHTTPErrorMessage.message(from: data, statusCode: nil, language: .chinese) == "AI 请求失败：Invalid API key（code=invalid_api_key）")
    }

    @Test
    func emptyBodyUsesStatusFallback() {
        #expect(AIHTTPErrorMessage.message(from: Data(), statusCode: 500, language: .chinese) == "AI 请求失败，HTTP 500。")
    }

    @Test
    func plainTextBodyIsIncluded() {
        let data = Data("Service unavailable".utf8)

        #expect(AIHTTPErrorMessage.message(from: data, statusCode: 503, language: .chinese) == "AI 请求失败，HTTP 503：Service unavailable")
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

        #expect(AIHTTPErrorMessage.message(from: data, statusCode: 401, language: .chinese) == "AI 请求失败，HTTP 401：Invalid API key（type=auth_error, code=invalid_api_key, param=Authorization）")
    }

    @Test
    func topLevelMessageIsUsedWhenPresent() {
        let data = Data(#"{"message":"Rate limited"}"#.utf8)

        #expect(AIHTTPErrorMessage.message(from: data, statusCode: 429, language: .chinese) == "AI 请求失败，HTTP 429：Rate limited")
    }
}

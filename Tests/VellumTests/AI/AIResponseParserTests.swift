import Foundation
import Testing
@testable import VellumCore

@Suite("AI response parser")
struct AIResponseParserTests {
    @Test
    func completionTextTrimsFirstChoiceContent() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"  explanation\n"}}]}"#.utf8)

        #expect(try AIResponseParser.completionText(from: data) == "explanation")
    }

    @Test
    func anthropicMessageTextJoinsTextBlocks() throws {
        let data = Data(#"{"content":[{"type":"text","text":"  hello"},{"type":"text","text":" world\n"}]}"#.utf8)

        #expect(try AIResponseParser.completionText(from: data, providerFormat: .anthropicMessages) == "hello world")
    }

    @Test
    func anthropicMessageSkipsThinkingAndToolBlocks() throws {
        let data = Data(#"{"content":[{"type":"thinking","thinking":"reasoning","signature":"sig"},{"type":"redacted_thinking","data":"private"},{"type":"tool_use","id":"tool","name":"lookup","input":{}},{"type":"text","text":"Answer"}],"stop_reason":"end_turn"}"#.utf8)

        #expect(try AIResponseParser.completionText(from: data, providerFormat: .anthropicMessages) == "Answer")
    }

    @Test(arguments: [AIProviderFormat.openAICompatible, .anthropicMessages])
    func rejectsTruncatedCompletion(format: AIProviderFormat) {
        let json = format == .anthropicMessages
            ? #"{"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}"#
            : #"{"choices":[{"message":{"role":"assistant","content":"partial"},"finish_reason":"length"}]}"#

        do {
            _ = try AIResponseParser.completionText(from: Data(json.utf8), providerFormat: format)
            Issue.record("Expected responseTruncated error")
        } catch AIExplanationError.responseTruncated {
            return
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func completionTextRejectsEmptyContent() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"  "}}]}"#.utf8)

        do {
            _ = try AIResponseParser.completionText(from: data)
            Issue.record("Expected emptyResponse error")
        } catch AIExplanationError.emptyResponse {
            return
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func modelIDsFiltersEmptyIDsAndSortsNaturally() throws {
        let data = Data(#"{"data":[{"id":"model-10"},{"id":""},{"id":"model-2"},{"id":"alpha"}]}"#.utf8)

        #expect(try AIResponseParser.modelIDs(from: data) == ["alpha", "model-2", "model-10"])
    }
}

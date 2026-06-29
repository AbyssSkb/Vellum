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

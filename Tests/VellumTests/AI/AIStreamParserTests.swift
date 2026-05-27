import Testing
@testable import VellumCore

@Suite("AI stream parser")
struct AIStreamParserTests {
    @Test
    func extractsDeltaContentFromDataLine() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#

        #expect(AIStreamParser.event(from: line) == .chunk("Hello"))
    }

    @Test
    func trimsPayloadWhitespace() {
        let line = #"data:   {"choices":[{"delta":{"content":" world"}}]}   "#

        #expect(AIStreamParser.event(from: line) == .chunk(" world"))
    }

    @Test
    func recognizesDoneMarker() {
        #expect(AIStreamParser.event(from: "data: [DONE]") == .done)
    }

    @Test
    func ignoresNonDataAndMalformedLines() {
        #expect(AIStreamParser.event(from: ": keep-alive") == .ignored)
        #expect(AIStreamParser.event(from: "data: {") == .ignored)
        #expect(AIStreamParser.event(from: #"data: {"choices":[{"delta":{}}]}"#) == .ignored)
        #expect(AIStreamParser.event(from: #"data: {"choices":[{"delta":{"content":""}}]}"#) == .ignored)
    }
}

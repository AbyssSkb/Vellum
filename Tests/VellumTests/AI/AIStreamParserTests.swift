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
    func recognizesFinishReason() {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#

        #expect(AIStreamParser.event(from: line) == .finished(reason: "stop"))
    }

    @Test
    func preservesContentWhenFinishReasonArrivesWithDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"done"},"finish_reason":"stop"}]}"#

        #expect(AIStreamParser.event(from: line) == .chunkAndFinished("done", reason: "stop"))
    }

    @Test
    func recognizesProviderErrorInsideSuccessfulHTTPStream() {
        let line = #"data: {"error":{"message":"Quota exhausted","type":"insufficient_quota","code":"quota","param":"model"}}"#

        guard case .error(let message) = AIStreamParser.event(from: line) else {
            Issue.record("Expected provider error")
            return
        }
        #expect(message.contains("Quota exhausted"))
        #expect(message.contains("type=insufficient_quota"))
        #expect(message.contains("code=quota"))
        #expect(message.contains("param=model"))
        #expect(!message.contains("HTTP"))
    }

    @Test
    func ignoresNonDataAndMalformedLines() {
        #expect(AIStreamParser.event(from: ": keep-alive") == .ignored)
        #expect(AIStreamParser.event(from: "data: {") == .ignored)
        #expect(AIStreamParser.event(from: #"data: {"choices":[{"delta":{}}]}"#) == .ignored)
        #expect(AIStreamParser.event(from: #"data: {"choices":[{"delta":{"content":""}}]}"#) == .ignored)
        #expect(AIStreamParser.event(from: #"data: {"error":null,"choices":[{"delta":{"content":"OK"}}]}"#) == .chunk("OK"))
    }
}

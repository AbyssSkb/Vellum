import Testing
@testable import VellumCore

@Suite("Codex app-server message parser")
struct CodexAppServerMessageParserTests {
    @Test
    func parsesModelIDs() {
        let message: [String: Any] = [
            "id": 1,
            "result": [
                "data": [
                    ["id": "gpt-5.5", "displayName": "GPT-5.5"],
                    ["id": "gpt-5.4", "displayName": "GPT-5.4"],
                    ["displayName": "No id"]
                ]
            ]
        ]

        #expect(CodexAppServerMessageParser.modelIDs(from: message) == ["gpt-5.5", "gpt-5.4"])
    }

    @Test
    func parsesAgentMessageDeltaForMatchingTurn() {
        let message: [String: Any] = [
            "method": "item/agentMessage/delta",
            "params": [
                "threadId": "thread",
                "turnId": "turn",
                "itemId": "item",
                "delta": "hello"
            ]
        ]

        #expect(CodexAppServerMessageParser.agentMessageDelta(from: message, threadID: "thread", turnID: "turn") == "hello")
        #expect(CodexAppServerMessageParser.agentMessageDelta(from: message, threadID: "other", turnID: "turn") == nil)
    }

    @Test
    func parsesCompletedAgentMessage() {
        let message: [String: Any] = [
            "method": "item/completed",
            "params": [
                "threadId": "thread",
                "turnId": "turn",
                "item": [
                    "type": "agentMessage",
                    "text": " done\n"
                ]
            ]
        ]

        #expect(CodexAppServerMessageParser.completedAgentMessage(from: message, threadID: "thread", turnID: "turn") == "done")
    }

    @Test(arguments: [false, true])
    func distinguishesTerminalAndRetryingErrors(willRetry: Bool) {
        let message: [String: Any] = [
            "method": "error",
            "params": [
                "threadId": "thread",
                "turnId": "turn",
                "willRetry": willRetry,
                "error": ["message": "Rate limit exceeded"]
            ]
        ]

        #expect(CodexAppServerMessageParser.errorMessage(from: message) == (willRetry ? nil : "Rate limit exceeded"))
    }

    @Test(arguments: ["failed", "interrupted"])
    func rejectsUnsuccessfulTurnsAndPreservesTheirError(status: String) throws {
        let message: [String: Any] = [
            "method": "turn/completed",
            "params": [
                "threadId": "thread",
                "turn": [
                    "id": "turn",
                    "status": status,
                    "items": [],
                    "error": ["message": "Generation stopped"]
                ]
            ]
        ]

        #expect(try !CodexAppServerMessageParser.isTurnCompleted(message, threadID: "other", turnID: "turn"))
        #expect(try !CodexAppServerMessageParser.isTurnCompleted(message, threadID: "thread", turnID: "other"))
        do {
            _ = try CodexAppServerMessageParser.isTurnCompleted(message, threadID: "thread", turnID: "turn")
            Issue.record("Expected the unsuccessful turn to throw")
        } catch AIExplanationError.server(let message) {
            #expect(message == "Generation stopped")
        }
    }

    @Test
    func recognizesSuccessfulTurn() throws {
        let message: [String: Any] = [
            "method": "turn/completed",
            "params": [
                "threadId": "thread",
                "turn": ["id": "turn", "status": "completed", "items": []]
            ]
        ]

        #expect(try CodexAppServerMessageParser.isTurnCompleted(message, threadID: "thread", turnID: "turn"))
    }
}

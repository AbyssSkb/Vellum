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
}

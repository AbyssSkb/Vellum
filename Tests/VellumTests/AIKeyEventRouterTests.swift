import AppKit
import Testing
@testable import Vellum

@Suite("AI key event router")
struct AIKeyEventRouterTests {
    @Test
    func escapeDismissesHoveredExplanationOnKeyDown() {
        #expect(AIKeyEventRouter.action(
            key: "\u{1b}",
            eventType: .keyDown,
            hasHoveredExplanation: true,
            continuousScrollKey: nil
        ) == .dismissHover)
    }

    @Test
    func escapeWithoutHoveredExplanationIsForwardedToWebView() {
        #expect(AIKeyEventRouter.action(
            key: "\u{1b}",
            eventType: .keyDown,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .forwardToWebView(key: "\u{1b}"))
    }

    @Test
    func jAndKStartContinuousScrollOnKeyDown() {
        #expect(AIKeyEventRouter.action(
            key: "j",
            eventType: .keyDown,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .startContinuousScroll(directionKey: "j"))
        #expect(AIKeyEventRouter.action(
            key: "k",
            eventType: .keyDown,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .startContinuousScroll(directionKey: "k"))
    }

    @Test
    func matchingScrollKeyStopsContinuousScrollOnKeyUp() {
        #expect(AIKeyEventRouter.action(
            key: "j",
            eventType: .keyUp,
            hasHoveredExplanation: false,
            continuousScrollKey: "j"
        ) == .stopContinuousScroll)
    }

    @Test
    func nonMatchingScrollKeyUpIsConsumedWithoutStopping() {
        #expect(AIKeyEventRouter.action(
            key: "j",
            eventType: .keyUp,
            hasHoveredExplanation: false,
            continuousScrollKey: "k"
        ) == .consume)
    }

    @Test
    func popoverCommandKeysForwardOnKeyDownAndConsumeOnKeyUp() {
        #expect(AIKeyEventRouter.action(
            key: "m",
            eventType: .keyDown,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .forwardToWebView(key: "m"))
        #expect(AIKeyEventRouter.action(
            key: "c",
            eventType: .keyUp,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .consume)
    }

    @Test
    func unrelatedKeysAreIgnored() {
        #expect(AIKeyEventRouter.action(
            key: "x",
            eventType: .keyDown,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .none)
        #expect(AIKeyEventRouter.action(
            key: "x",
            eventType: .keyUp,
            hasHoveredExplanation: false,
            continuousScrollKey: nil
        ) == .none)
    }
}

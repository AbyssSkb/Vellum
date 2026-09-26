import AppKit
import Testing
@testable import VellumCore

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

    @Test(arguments: [NSEvent.ModifierFlags.command, .control, .option], [UInt16(38), 5])
    @MainActor
    func modifiedKeyUpStopsActiveScroll(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) throws {
        let view = VellumPDFView()
        view.aiInteraction.activeExplanationModel = AIExplanationPopoverModel(title: "test")
        let keyDown = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: keyCode
        ))
        #expect(view.handleAIKeyEvent(keyDown))
        let event = try #require(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: keyCode
        ))
        #expect(view.handleAIKeyEvent(event))
        #expect(view.aiInteraction.continuousScrollKey == nil)
        #expect(view.aiInteraction.continuousScrollKeyCode == nil)
    }

    @Test
    @MainActor
    func deactivationStopsActiveScrollAndAllowsRestart() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.showPopover(model: AIExplanationPopoverModel(title: "test"), at: nil, kind: .hover)
        view.startAIContinuousScroll("j", keyCode: 38)
        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)
        #expect(view.aiInteraction.continuousScrollKey == nil)
        view.startAIContinuousScroll("j", keyCode: 38)
        #expect(view.aiInteraction.continuousScrollKey == "j")
        view.hideAIExplanationPopover()
        #expect(view.aiInteraction.continuousScrollKey == nil)
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

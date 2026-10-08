import AppKit
import Testing
@preconcurrency import WebKit
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

    @Test
    @MainActor
    func escapeBeforeWebViewRegistrationCancelsStreamingExplanation() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.hideAIExplanationPopover(); window.contentView = nil; window.close() }
        view.showPopover(model: AIExplanationPopoverModel(title: "test", isStreaming: true), at: nil, kind: .streaming)
        let request = Task<Void, Never> {}
        view.aiInteraction.explanationTask = request
        view.aiInteraction.explanationRequestID = UUID()
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))

        #expect(view.aiInteraction.activeWebView == nil)
        #expect(view.handleAIKeyEvent(event))
        #expect(view.aiInteraction.activeExplanationModel == nil)
        #expect(view.aiInteraction.explanationOverlay == nil)
        #expect(view.aiInteraction.explanationRequestID == nil)
        #expect(view.aiInteraction.explanationTask == nil)
        #expect(request.isCancelled)
    }

    @Test
    @MainActor
    func registeredWebViewReceivesEscapeWithoutNativeFallback() throws {
        _ = NSApplication.shared
        let view = VellumPDFView()
        let model = AIExplanationPopoverModel(title: "test")
        view.aiInteraction.activeExplanationModel = model
        let webView = AIExplanationWebView()
        defer { view.hideAIExplanationPopover(); webView.stopLoading() }
        var dismissals = 0
        webView.onDismiss = { dismissals += 1 }
        view.aiInteraction.activeWebView = webView
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))

        #expect(view.handleAIKeyEvent(event))
        #expect(dismissals == 1)
        #expect(view.aiInteraction.activeExplanationModel === model)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func repeatedScrollKeyStartsAfterWebViewRegistration() async throws {
        _ = NSApplication.shared
        let view = VellumPDFView()
        view.aiInteraction.activeExplanationModel = AIExplanationPopoverModel(title: "test")
        let keyDown = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: 38
        ))
        #expect(view.handleAIKeyEvent(keyDown))
        #expect(view.aiInteraction.continuousScrollKey == "j")

        let webView = AIExplanationWebView()
        let probe = AIKeyEventNavigationProbe()
        webView.navigationDelegate = probe
        defer { view.hideAIExplanationPopover(); webView.stopLoading() }
        try await probe.load(AIExplanationHTML.document.replacingOccurrences(
            of: #"<script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>"#,
            with: ""
        ), in: webView)
        view.aiInteraction.activeWebView = webView
        #expect(try await webView.evaluateJavaScript("scrollState.direction") as? Int == 0)
        let repeatedKeyDown = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: true, keyCode: 38
        ))

        #expect(view.handleAIKeyEvent(repeatedKeyDown))
        #expect(try await webView.evaluateJavaScript("scrollState.direction") as? Int == 1)
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
    func markedTextPreservesCompositionAndStopsReleasedScrollKey() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.hideAIExplanationPopover(); window.contentView = nil; window.close() }
        let overlay = NSView(frame: view.bounds)
        view.addSubview(overlay)
        view.aiInteraction.explanationOverlay = overlay
        view.aiInteraction.activeExplanationModel = AIExplanationPopoverModel(title: "test")
        let editor = NSTextView(frame: overlay.bounds)
        overlay.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        let keyDown = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: 38
        ))
        #expect(view.handleAIKeyEvent(keyDown))
        editor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        #expect(!view.handleAIKeyEvent(keyDown))
        #expect(view.aiInteraction.continuousScrollKey == "j")
        let keyUp = try #require(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: 38
        ))

        #expect(view.handleAIKeyEvent(keyUp))
        #expect(view.aiInteraction.continuousScrollKey == nil)
        #expect(view.aiInteraction.continuousScrollKeyCode == nil)
        #expect(editor.hasMarkedText())
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

@MainActor
private final class AIKeyEventNavigationProbe: NSObject, WKNavigationDelegate {
    private var loading: CheckedContinuation<Void, Error>?
    private var loadingNavigation: WKNavigation?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            loadingNavigation = webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === loadingNavigation else { return }
        loading?.resume()
        loading = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === loadingNavigation else { return }
        loading?.resume(throwing: error)
        loading = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
}

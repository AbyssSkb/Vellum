import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("AI conversation transcript", .serialized)
@MainActor
struct AIConversationTranscriptTests {
    @Test(.timeLimit(.minutes(1)))
    func unchangedPayloadPreservesSelectionAndExplicitScrollStillWorks() async throws {
        let fixture = TranscriptFixture()
        defer { fixture.close() }
        let message = AIConversationMessage(role: .assistant, content: Self.longAnswer)
        fixture.render([message], followBottom: true)
        try await fixture.load()
        _ = try await fixture.webView.evaluateJavaScript("""
            window.savedMessages = document.querySelector('.messages');
            const text = document.querySelector('.assistant-markdown p').firstChild;
            const range = document.createRange();
            range.setStart(text, 0); range.setEnd(text, 6);
            const selection = window.getSelection();
            selection.removeAllRanges(); selection.addRange(range);
            window.scrollTo(0, 0); null;
            """)

        for _ in 0..<3 { fixture.render([message], followBottom: false) }
        try await fixture.settle()
        #expect(try await fixture.webView.evaluateJavaScript("window.transcriptRenders.length") as? Int == 1)
        #expect(try await fixture.webView.evaluateJavaScript("window.savedMessages === document.querySelector('.messages')") as? Bool == true)
        #expect(try await fixture.webView.evaluateJavaScript("window.getSelection().toString()") as? String == "Answer")
        #expect(try await fixture.webView.evaluateJavaScript("window.scrollY") as? Double == 0)

        fixture.render([message], followBottom: true)
        try await fixture.settle()
        #expect(try await fixture.webView.evaluateJavaScript("window.transcriptRenders.length") as? Int == 1)
        #expect(try await fixture.webView.evaluateJavaScript("window.savedMessages === document.querySelector('.messages')") as? Bool == true)
        #expect(try await fixture.webView.evaluateJavaScript("window.scrollY > 0 && isNearBottom()") as? Bool == true)

        var updated = message
        updated.content = "Updated answer"
        fixture.render([updated], followBottom: false)
        try await fixture.settle()
        #expect(try await fixture.webView.evaluateJavaScript("window.transcriptRenders.length") as? Int == 2)
        #expect(try await fixture.webView.evaluateJavaScript("document.getElementById('content').textContent.includes('Updated answer')") as? Bool == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func pendingUpdatesKeepLatestPayloadAndAnyExplicitFollowRequest() async throws {
        let fixture = TranscriptFixture()
        defer { fixture.close() }
        fixture.render([AIConversationMessage(role: .assistant, content: "Previous answer")], followBottom: false)
        let latest = AIConversationMessage(role: .assistant, content: Self.longAnswer)
        fixture.render([latest], followBottom: true)
        fixture.render([latest], followBottom: false)

        try await fixture.load()

        #expect(try await fixture.webView.evaluateJavaScript("window.transcriptRenders.length") as? Int == 1)
        #expect(try await fixture.webView.evaluateJavaScript("window.transcriptRenders[0].followBottom") as? Bool == true)
        #expect(try await fixture.webView.evaluateJavaScript("window.transcriptRenders[0].payload.messages[0].content") as? String == Self.longAnswer)
        #expect(try await fixture.webView.evaluateJavaScript("window.scrollY > 0 && isNearBottom()") as? Bool == true)
    }

    private static let longAnswer = (1...30).map { "Answer paragraph \($0) with enough content to scroll." }.joined(separator: "\n\n")
}

@MainActor
private final class TranscriptFixture: NSObject, WKNavigationDelegate {
    let webView: AIConversationTranscriptWKWebView
    private let window: NSWindow
    private var loaded = false
    private var loadingError: Error?

    override init() {
        _ = NSApplication.shared
        webView = AIConversationTranscriptWKWebView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220), styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        webView.stopLoading()
        webView.navigationDelegate = self
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
    }

    func render(_ messages: [AIConversationMessage], followBottom: Bool) {
        webView.render(messages: messages, errorMessage: nil, isSending: false, thinkingText: "Thinking", followBottom: followBottom)
    }

    func load() async throws {
        let instrumentation = """
            <script>
            // These checks exercise DOM updates and scrolling, independent of window visibility.
            window.requestAnimationFrame = function(callback) { callback(performance.now()); return 0; };
            window.transcriptRenders = [];
            const originalRender = window.vellumSetConversation;
            window.vellumSetConversation = function(payload, followBottom) {
              window.transcriptRenders.push({payload, followBottom});
              originalRender(payload, followBottom);
            };
            </script>
            """
        let document = AIConversationTranscriptHTML.document
            .replacingOccurrences(of: #"<script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>"#, with: "")
            .replacingOccurrences(of: "</body>", with: instrumentation + "</body>")
        webView.loadHTMLString(document, baseURL: nil)
        try await waitForTestCondition("Conversation transcript document loaded") { self.loaded || self.loadingError != nil }
        if let loadingError { throw loadingError }
        try await settle()
    }

    func settle() async throws {
        _ = try await webView.evaluateJavaScript("null;")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView.webView(webView, didFinish: navigation)
        loaded = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { loadingError = error }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingError = error
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        window.close()
    }
}

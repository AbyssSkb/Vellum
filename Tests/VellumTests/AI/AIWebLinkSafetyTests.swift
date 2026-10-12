import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("AI Markdown rendering", .serialized)
@MainActor
struct AIWebLinkSafetyTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func markdownAndGeneratedMathLinksCannotInvokeNativeCommands(conversation: Bool) async throws {
        let fixture = AIWebRenderingFixture(conversation: conversation)
        defer { fixture.close() }
        try await fixture.load()
        let webView = fixture.webView
        let probe = fixture.probe
        let command = "window.webkit.messageHandlers.vellum.postMessage%28%27highlight%27%29"
        let unsafeDestinations = [
            "javascript:\(command)", "JaVaScRiPt:\(command)", "java\tscript:\(command)",
            "data:text/html,test", "file:///etc/passwd", "vellum://highlight",
            "//example.com", "/relative", "jav&#x61;script:\(command)"
        ]
        let safeDestinations = [
            "http://example.com/reference", "https://example.com/?a=1&b=2",
            "mailto:reader@example.com", "https://example.com/\" onmouseover=\"\(command)",
            "https://example.com/@@BLOCK_0@@",
            "https://example.com/@@INLINE_MATH_0@@"
        ]
        let markdown = (unsafeDestinations + safeDestinations).enumerated()
            .map { "[link\($0.offset)](\($0.element))" }.joined(separator: "\n") + " $y$\n\n$$x$$"
        try await fixture.render(markdown)
        let destinations = try #require(try await webView.evaluateJavaScript(
            "Array.from(document.querySelectorAll('#content a'), a => a.getAttribute('href'));"
        ) as? [String])
        #expect(destinations == safeDestinations)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('.math-display').length") as? Int == 1)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('[onmouseover]').length") as? Int == 0)

        try await probe.runAndWaitForMessages(
            "document.querySelectorAll('#content a').forEach(a => { a.dispatchEvent(new Event('mouseover')); a.click(); });",
            in: webView
        )
        #expect(probe.commands.isEmpty)

        let mathDestinations = [
            "javascript:\(command)", "JaVaScRiPt:\(command)", "java\tscript:\(command)",
            "https://example.com/math", "http://example.com/math", "mailto:reader@example.com"
        ]
        let mathLiteral = String(decoding: try JSONSerialization.data(withJSONObject: mathDestinations), as: UTF8.self)
        try await probe.runAndWaitForMessages("""
            window.vellumMathLinkClicks = [];
            for (const svg of [false, true]) {
              for (const href of \(mathLiteral)) {
                // Simulate anchors added later by MathJax's CHTML/SVG output.
                const container = svg
                  ? document.createElementNS('http://www.w3.org/2000/svg', 'svg')
                  : document.createElement('mjx-container');
                const anchor = svg
                  ? document.createElementNS('http://www.w3.org/2000/svg', 'a')
                  : document.createElement('a');
                const child = svg
                  ? document.createElementNS('http://www.w3.org/2000/svg', 'g')
                  : document.createElement('mjx-mi');
                if (svg) {
                  anchor.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', href);
                } else {
                  anchor.setAttribute('href', href);
                }
                anchor.appendChild(child);
                container.appendChild(anchor);
                document.getElementById('content').appendChild(container);
                const event = new MouseEvent('click', {bubbles:true, cancelable:true});
                child.dispatchEvent(event);
                window.vellumMathLinkClicks.push(event.defaultPrevented);
              }
            }
            """, in: webView)
        let preventedMathClicks = try #require(try await webView.evaluateJavaScript("window.vellumMathLinkClicks") as? [Bool])
        #expect(preventedMathClicks == [true, true, true, false, false, false, true, true, true, false, false, false])
        #expect(probe.commands.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func markdownFormattingPreservesLiteralCodeAndSharedForeground(conversation: Bool) async throws {
        let fixture = AIWebRenderingFixture(conversation: conversation)
        defer { fixture.close() }
        try await fixture.load()
        let webView = fixture.webView
        let webColor = try #require(try await webView.evaluateJavaScript(
            "getComputedStyle(document.body).color.match(/\\d+/g).map(Number);"
        ) as? [Int])
        let foreground = try #require(VellumColors.foreground.usingColorSpace(.sRGB))
        #expect(webColor == [foreground.redComponent, foreground.greenComponent, foreground.blueComponent].map { Int(($0 * 255).rounded()) })

        let inlineCode = #"**strong** *emphasis* [reference](https://example.com) $x_y$ $$z$$ \(a_b\) <tag> & @@BLOCK_0@@ @@INLINE_MATH_0@@ @@INLINE_CODE_0@@"#
        let markers = "@@BLOCK_0@@ @@INLINE_MATH_0@@ @@INLINE_CODE_0@@ @@@BLOCK_0@@"
        let codeMarkdown = "`\(inlineCode)`\n\n\(markers)\n\n**bold** *emphasis* [reference](https://example.com) $x_y$\n\n```javascript\nconst tag = '<node>';\n```\n\n```\nplain & literal\n```\n\n$$outside$$\n\nBefore ` unmatched\n\n```swift\nlet value = 1\n```\n\nAfter ` unmatched"
        try await fixture.render(codeMarkdown)
        let codeContents = try #require(try await webView.evaluateJavaScript(
            "Array.from(document.querySelectorAll('#content code'), code => code.textContent);"
        ) as? [String])
        #expect(codeContents == [inlineCode, "const tag = '<node>';", "plain & literal", "let value = 1"])
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('code > *').length") as? Int == 0)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('#content strong').length") as? Int == 1)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('#content em').length") as? Int == 1)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('#content a').length") as? Int == 1)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('.math-display').length") as? Int == 1)
        let renderedText = try #require(try await webView.evaluateJavaScript("document.getElementById('content').textContent") as? String)
        #expect(renderedText.contains(markers))
    }

    @Test(.timeLimit(.minutes(1)))
    func explanationControlsSendExplicitNativeCommands() async throws {
        let fixture = AIWebRenderingFixture(conversation: false)
        defer { fixture.close() }
        try await fixture.load()
        _ = try await fixture.webView.evaluateJavaScript("window.vellumSetPronunciationSpeech('test', 'US', 'UK'); null;")
        try await fixture.render("## Pronunciation\n/test/\nSecond paragraph\n## Reading\n- item\nAfter list")
        #expect(try await fixture.webView.evaluateJavaScript("document.querySelectorAll('.heading-row').length") as? Int == 2)
        #expect(try await fixture.webView.evaluateJavaScript("document.querySelectorAll('.pronunciation-line').length") as? Int == 1)
        #expect(try await fixture.webView.evaluateJavaScript("document.querySelectorAll('.speak-button').length") as? Int == 2)
        try await fixture.probe.runAndWaitForMessages(
            "document.querySelector('.speak-button').click(); postVellumCommand('highlight');",
            in: fixture.webView
        )
        #expect(fixture.probe.commands == ["speakPronunciationUS", "highlight"])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func backslashMathDelimitersPreserveTextInsteadOfEmphasis(conversation: Bool) async throws {
        let fixture = AIWebRenderingFixture(conversation: conversation)
        defer { fixture.close() }
        try await fixture.load()
        try await fixture.render(#"Before \(a*b*c\) after"# + "\n\n" + #"\[x*y*z\]"#)
        let webView = fixture.webView
        let text = try #require(try await webView.evaluateJavaScript("document.getElementById('content').textContent") as? String)
        #expect(text.contains(#"\(a*b*c\)"#))
        #expect(text.contains(#"\[x*y*z\]"#))
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('.math-display').length") as? Int == 1)
        #expect(try await webView.evaluateJavaScript("document.querySelectorAll('#content em').length") as? Int == 0)
    }

    @Test
    func nativeNavigationPolicyCancelsUnsafeLinksAndAllowsDocumentLoading() throws {
        for destination in ["javascript:alert(1)", "data:text/html,test", "file:///etc/passwd", "vellum://highlight"] {
            let action = AIWebNavigationAction(url: try #require(URL(string: destination)), type: .linkActivated)
            var decision: WKNavigationActionPolicy?
            AIWebLinkNavigationPolicy.decide(for: action) { decision = $0 }
            #expect(decision == .cancel)
        }
        let documentLoad = AIWebNavigationAction(url: try #require(URL(string: "about:blank")), type: .other)
        var decision: WKNavigationActionPolicy?
        AIWebLinkNavigationPolicy.decide(for: documentLoad) { decision = $0 }
        #expect(decision == .allow)
    }
}

@MainActor
private struct AIWebRenderingFixture {
    let webView: WKWebView
    let probe = AIWebLinkSafetyProbe()
    let conversation: Bool

    init(conversation: Bool) {
        _ = NSApplication.shared
        self.conversation = conversation
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(probe, name: "vellum")
        configuration.userContentController.add(probe, name: "vellumConversation")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), configuration: configuration)
        webView.navigationDelegate = probe
    }

    func load() async throws {
        let document = conversation ? AIConversationTranscriptHTML.document : AIExplanationHTML.document
        // Exercise generated MathJax anchors locally without depending on the CDN.
        try await probe.load(document.replacingOccurrences(
            of: #"<script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>"#,
            with: ""
        ), in: webView)
    }

    func render(_ markdown: String) async throws {
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: [markdown]), as: UTF8.self)
        let script = conversation
            ? "window.vellumSetConversation({messages:[{role:'assistant',content:\(literal)[0]}]}, false);"
            : "window.vellumSetMarkdown(\(literal)[0], false);"
        _ = try await webView.evaluateJavaScript(script + "null;")
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
}

private final class AIWebNavigationAction: WKNavigationAction {
    private let url: URL
    private let type: WKNavigationType

    init(url: URL, type: WKNavigationType) {
        self.url = url
        self.type = type
        super.init()
    }

    override var request: URLRequest { URLRequest(url: url) }
    override var navigationType: WKNavigationType { type }
}

@MainActor
private final class AIWebLinkSafetyProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var commands: [String] = []
    private var didFinishLoading = false
    private var loadingError: Error?
    private var messageBarriers = 0

    func load(_ html: String, in webView: WKWebView) async throws {
        webView.loadHTMLString(html, baseURL: nil)
        try await waitForTestCondition("AI Markdown document loaded") { didFinishLoading || loadingError != nil }
        if let loadingError { throw loadingError }
    }

    func runAndWaitForMessages(_ script: String, in webView: WKWebView) async throws {
        let previousBarriers = messageBarriers
        _ = try await webView.evaluateJavaScript(script + ";window.webkit.messageHandlers.vellum.postMessage('barrier'); null;")
        try await waitForTestCondition("AI Markdown native messages received") { messageBarriers > previousBarriers }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishLoading = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingError = error
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingError = error
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let command = message.body as? String else { return }
        if command == "barrier" {
            messageBarriers += 1
        } else {
            commands.append(command)
        }
    }
}

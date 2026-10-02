import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("AI Markdown rendering", .serialized)
@MainActor
struct AIWebLinkSafetyTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func markdownLinksAndCodeProtectLiteralContentAndNativeCommands(conversation: Bool) async throws {
        _ = NSApplication.shared
        let probe = AIWebLinkSafetyProbe()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(probe, name: "vellum")
        configuration.userContentController.add(probe, name: "vellumConversation")
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), configuration: configuration)
        webView.navigationDelegate = probe
        defer {
            webView.stopLoading()
            configuration.userContentController.removeAllScriptMessageHandlers()
        }
        let document = conversation ? AIConversationTranscriptHTML.document : AIExplanationHTML.document
        try await probe.load(document.replacingOccurrences(
            of: #"<script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>"#,
            with: ""
        ), in: webView)

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
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: [markdown]), as: UTF8.self)
        let render = conversation
            ? "window.vellumSetConversation({messages:[{role:'assistant',content:\(literal)[0]}]}, false);"
            : "window.vellumSetMarkdown(\(literal)[0], false);"
        _ = try await webView.evaluateJavaScript(render + "null;")
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

        let inlineCode = #"**strong** *emphasis* [reference](https://example.com) $x_y$ $$z$$ \(a_b\) <tag> & @@BLOCK_0@@ @@INLINE_MATH_0@@ @@INLINE_CODE_0@@"#
        let markers = "@@BLOCK_0@@ @@INLINE_MATH_0@@ @@INLINE_CODE_0@@ @@@BLOCK_0@@"
        let codeMarkdown = "`\(inlineCode)`\n\n\(markers)\n\n**bold** *emphasis* [reference](https://example.com) $x_y$\n\n```javascript\nconst tag = '<node>';\n```\n\n```\nplain & literal\n```\n\n$$outside$$\n\nBefore ` unmatched\n\n```swift\nlet value = 1\n```\n\nAfter ` unmatched"
        let codeLiteral = String(decoding: try JSONSerialization.data(withJSONObject: [codeMarkdown]), as: UTF8.self)
        let renderCode = conversation
            ? "window.vellumSetConversation({messages:[{role:'assistant',content:\(codeLiteral)[0]}]}, false);"
            : "window.vellumSetMarkdown(\(codeLiteral)[0], false);"
        _ = try await webView.evaluateJavaScript(renderCode + "null;")
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

        if !conversation {
            _ = try await webView.evaluateJavaScript("window.vellumSetPronunciationSpeech('test', 'US', 'UK'); window.vellumSetMarkdown('## Pronunciation\\n/test/', false); null;")
            try await probe.runAndWaitForMessages(
                "document.querySelector('.speak-button').click(); postVellumCommand('highlight');",
                in: webView
            )
            #expect(probe.commands == ["speakPronunciationUS", "highlight"])
        }
    }
}

@MainActor
private final class AIWebLinkSafetyProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var commands: [String] = []
    private var loading: CheckedContinuation<Void, Error>?
    private var messageBarrier: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func runAndWaitForMessages(_ script: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            messageBarrier = continuation
            webView.evaluateJavaScript(script + ";window.webkit.messageHandlers.vellum.postMessage('barrier'); null;") { [weak self] _, error in
                if let error {
                    self?.messageBarrier?.resume(throwing: error)
                    self?.messageBarrier = nil
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading?.resume()
        loading = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: error)
        loading = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let command = message.body as? String else { return }
        if command == "barrier" {
            messageBarrier?.resume()
            messageBarrier = nil
        } else {
            commands.append(command)
        }
    }
}

import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary early presentation", .serialized)
@MainActor
struct DictionaryEarlyPresentationTests {
    @Test(.timeLimit(.minutes(1)))
    func reportsVisibleContentWhileALaterDictionaryScriptIsStillLoading() async throws {
        let popover = DictionaryPopoverView()
        defer { popover.stop() }
        let script = try #require(popover.webView.configuration.userContentController.userScripts.first {
            $0.source == DictionaryPage.presentationScript
        })
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(script)
        let probe = DictionaryEarlyPresentationProbe()
        configuration.userContentController.add(probe, contentWorld: .defaultClient, name: "dictionary")
        let handler = DictionaryPendingScriptHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: DictionaryPage.scheme)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        webView.navigationDelegate = probe
        defer {
            handler.finishPendingScript()
            webView.stopLoading()
            webView.navigationDelegate = nil
            configuration.userContentController.removeAllScriptMessageHandlers()
            configuration.userContentController.removeAllUserScripts()
        }
        webView.load(URLRequest(url: DictionaryPage.entryURL(id: UUID())))
        try await waitForTestCondition("Dictionary content is presented before its pending script finishes") {
            (probe.height > 0 && handler.pendingTask != nil) || probe.error != nil
        }
        if let error = probe.error { throw error }
        #expect(probe.height > 0)
        #expect(handler.pendingTask != nil)
        #expect(!probe.finished)
        #expect(try await webView.evaluateJavaScript("document.readyState") as? String == "loading")

        handler.finishPendingScript()
        try await waitForTestCondition("Dictionary document finishes after the pending script is released") {
            probe.finished || probe.error != nil
        }
        if let error = probe.error { throw error }
        #expect(probe.finished)
        #expect(try await webView.evaluateJavaScript("window.dictionaryPendingScriptFinished") as? Bool == true)
    }
}

@MainActor
private final class DictionaryEarlyPresentationProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var height: Double = 0
    var finished = false
    var error: Error?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "layout",
              let height = body["height"] as? NSNumber else { return }
        self.height = height.doubleValue
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.error = error }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { self.error = error }
}

@MainActor
private final class DictionaryPendingScriptHandler: NSObject, WKURLSchemeHandler {
    private(set) var pendingTask: (any WKURLSchemeTask)?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        if url.path == "/pending.js" {
            pendingTask = urlSchemeTask
            return
        }
        let html = DictionaryPage.document("<h1>ready</h1><script src='pending.js'></script>")
        let data = Data(html.utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        if let pendingTask, pendingTask === urlSchemeTask { self.pendingTask = nil }
    }

    func finishPendingScript() {
        guard let task = pendingTask, let url = task.request.url else { return }
        pendingTask = nil
        let data = Data("window.dictionaryPendingScriptFinished = true;".utf8)
        task.didReceive(URLResponse(url: url, mimeType: "text/javascript", expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }
}

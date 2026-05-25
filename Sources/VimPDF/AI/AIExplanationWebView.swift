@preconcurrency import AppKit
import Foundation
import WebKit

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

final class AIExplanationWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    var onDismiss: (() -> Void)?
    var onHighlight: (() -> Void)?
    var onCycleColor: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var shouldFocusWhenReady = true
    var autoScrollOnUpdate = false
    private var pendingMarkdown = ""
    private var didLoadDocument = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "vimpdf")
        setValue(false, forKey: "drawsBackground")
        loadHTMLString(AIExplanationHTML.document, baseURL: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func render(_ markdown: String) {
        pendingMarkdown = markdown
        guard didLoadDocument else { return }

        let encoded = Self.javascriptString(markdown)
        evaluateJavaScript("window.vimpdfSetMarkdown(\(encoded), \(autoScrollOnUpdate ? "true" : "false"));")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoadDocument = true
        render(pendingMarkdown)
        if shouldFocusWhenReady {
            window?.makeFirstResponder(self)
        }
    }

    func handleKey(_ key: String) -> Bool {
        switch key {
        case "j":
            pulseScroll(direction: 1)
        case "k":
            pulseScroll(direction: -1)
        case "m":
            onHighlight?()
        case "c":
            onCycleColor?()
        case "\u{1b}":
            onDismiss?()
        default:
            return false
        }

        return true
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }

        let key = event.charactersIgnoringModifiers?.lowercased()
        switch key {
        case "j":
            startContinuousScroll(direction: 1)
        case "k":
            startContinuousScroll(direction: -1)
        default:
            if handleKey(key ?? "") == false {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyUp(with: event)
            return
        }

        let key = event.charactersIgnoringModifiers?.lowercased()
        switch key {
        case "j", "k":
            stopContinuousScroll()
        default:
            super.keyUp(with: event)
        }
    }

    func startContinuousScroll(direction: Int) {
        evaluateJavaScript("window.vimpdfStartScroll(\(direction));")
    }

    func stopContinuousScroll() {
        evaluateJavaScript("window.vimpdfStopScroll();")
    }

    func pulseScroll(direction: Int) {
        evaluateJavaScript("window.vimpdfPulseScroll(\(direction));")
    }

    func scrollToTop() {
        evaluateJavaScript("window.vimpdfScrollToTop();")
    }

    func scrollToBottom() {
        evaluateJavaScript("window.vimpdfScrollToBottom();")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vimpdf" else { return }

        if let command = message.body as? String {
            _ = handleCommand(command)
            return
        }

        guard let payload = message.body as? [String: Any],
              let command = payload["command"] as? String else { return }

        switch command {
        case "contentHeight":
            guard let height = payload["height"] as? NSNumber else { return }
            onContentHeightChange?(CGFloat(truncating: height))
        default:
            _ = handleCommand(command)
        }
    }

    @discardableResult
    private func handleCommand(_ command: String) -> Bool {
        switch command {
        case "startScrollDown":
            startContinuousScroll(direction: 1)
        case "startScrollUp":
            startContinuousScroll(direction: -1)
        case "stopScroll":
            stopContinuousScroll()
        case "scrollDown":
            pulseScroll(direction: 1)
        case "scrollUp":
            pulseScroll(direction: -1)
        default:
            return handleKey(Self.key(for: command))
        }

        return true
    }

    private static func key(for command: String) -> String {
        switch command {
        case "highlight":
            return "m"
        case "cycleColor":
            return "c"
        case "dismiss":
            return "\u{1b}"
        default:
            return ""
        }
    }

    private static func javascriptString(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }

        return String(encoded.dropFirst().dropLast())
    }

}

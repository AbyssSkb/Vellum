@preconcurrency import AppKit
import AVFoundation
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
    var pronunciationSpeechText: String?
    var autoPronunciationLanguageCode: String?
    var speakAmericanButtonTitle = "Speak American pronunciation"
    var speakBritishButtonTitle = "Speak British pronunciation"
    private var pendingMarkdown = ""
    private var didLoadDocument = false
    private var lastAutoPronouncedKey: String?
    private let speechSynthesizer = AVSpeechSynthesizer()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "vellum")
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
        let resolvedSpeechText = AIExplanationPronunciationSpeech.speechText(
            selectedText: pronunciationSpeechText,
            markdown: markdown
        )
        let speechText = Self.javascriptString(resolvedSpeechText ?? "")
        let usTitle = Self.javascriptString(speakAmericanButtonTitle)
        let ukTitle = Self.javascriptString(speakBritishButtonTitle)
        evaluateJavaScript("window.vellumSetPronunciationSpeech(\(speechText), \(usTitle), \(ukTitle));")
        evaluateJavaScript("window.vellumSetMarkdown(\(encoded), \(autoScrollOnUpdate ? "true" : "false"));")
        autoPronounceIfNeeded(speechText: resolvedSpeechText, markdown: markdown)
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
        evaluateJavaScript("window.vellumStartScroll(\(direction));")
    }

    func stopContinuousScroll() {
        evaluateJavaScript("window.vellumStopScroll();")
    }

    func pulseScroll(direction: Int) {
        evaluateJavaScript("window.vellumPulseScroll(\(direction));")
    }

    func scrollToTop() {
        evaluateJavaScript("window.vellumScrollToTop();")
    }

    func scrollToBottom() {
        evaluateJavaScript("window.vellumScrollToBottom();")
    }

    func stopPronunciation() {
        guard speechSynthesizer.isSpeaking else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vellum" else { return }

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
        case "speakPronunciationUS":
            speakPronunciation(languageCode: "en-US")
        case "speakPronunciationUK":
            speakPronunciation(languageCode: "en-GB")
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

    private func speakPronunciation(languageCode: String) {
        guard let text = AIExplanationPronunciationSpeech.speechText(
            selectedText: pronunciationSpeechText,
            markdown: pendingMarkdown
        ) else {
            NSSound.beep()
            return
        }

        if speechSynthesizer.isSpeaking {
            stopPronunciation()
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        speechSynthesizer.speak(utterance)
    }

    private func autoPronounceIfNeeded(speechText: String?, markdown: String) {
        guard let languageCode = autoPronunciationLanguageCode,
              let speechText,
              !speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !markdown.hasPrefix("vellum-loading:") else {
            lastAutoPronouncedKey = nil
            return
        }

        let key = "\(languageCode)\n\(speechText)\n\(markdown)"
        guard lastAutoPronouncedKey != key else { return }
        lastAutoPronouncedKey = key

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self,
                  self.autoPronunciationLanguageCode == languageCode,
                  self.lastAutoPronouncedKey == key else { return }
            self.speakPronunciation(languageCode: languageCode)
        }
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

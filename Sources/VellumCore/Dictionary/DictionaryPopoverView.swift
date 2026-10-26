@preconcurrency import AppKit
import AVFoundation
import SwiftUI
import WebKit

@MainActor
final class DictionaryPopoverView: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    var onDismiss: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    private(set) var preferredHeight: CGFloat = 160
    private var contentHeight: CGFloat?
    private let model = DictionaryPopoverModel()
    private let resourceHandler: DictionaryResourceHandler
    let webView: WKWebView
    private var lookupTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private(set) var player: AVAudioPlayer?
    private var activeNavigation: WKNavigation?
    private var lookupID = UUID()
    private var location = URL(fileURLWithPath: "/")
    private var pendingAnchor: String?
    private var didAutoPronounce = false
    private var pendingG = false
    private var scrollingKeyCode: UInt16?
    private var scrollingKey: String?

    var isLoading: Bool { model.isLoading }

    init() {
        let resourceHandler = DictionaryResourceHandler()
        self.resourceHandler = resourceHandler
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(resourceHandler, forURLScheme: DictionaryPage.scheme)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: DictionaryPage.linkCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: DictionaryPage.scrollScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: DictionaryPage.presentationScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        webView.navigationDelegate = self
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.setValue(false, forKey: "drawsBackground")
        configuration.userContentController.add(WeakScriptMessageHandler(self), contentWorld: .defaultClient, name: "dictionary")
        model.onDismiss = { [weak self] in self?.dismiss() }
        let host = NSHostingView(rootView: DictionaryPopoverSurface(model: model, webView: webView))
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func lookup(_ text: String) {
        lookup(text, anchor: nil)
    }

    private func lookup(_ text: String, anchor: String?) {
        stop()
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.word = word
        model.audioStatus = nil
        contentHeight = nil
        updatePreferredHeight()
        didAutoPronounce = false
        pendingAnchor = anchor
        guard !word.isEmpty else {
            model.message = language.text(.dictionaryNoSelection)
            return
        }
        model.isLoading = true
        model.message = language.text(.dictionaryLoading)
        let id = lookupID
        guard let location = AppPreferences.dictionaryLocation() else {
            showMessage(language.text(.dictionaryUnavailable))
            return
        }
        self.location = location
        lookupTask = Task { [weak self] in
            do {
                let entry = try await DictionaryStore.shared.lookup(word, at: location)
                guard !Task.isCancelled, let self, self.lookupID == id else { return }
                guard let entry else {
                    self.showMessage(self.language.text(.dictionaryNotFound(word)))
                    return
                }
                self.model.word = entry.word
                let url = DictionaryPage.entryURL(id: id)
                self.resourceHandler.setDocument(entry.html, at: url, location: location)
                self.activeNavigation = self.webView.load(URLRequest(url: url))
            } catch {
                guard !Task.isCancelled, let self, self.lookupID == id else { return }
                self.showMessage(self.message(for: error))
            }
        }
    }

    func stop() {
        pendingG = false
        scrollingKeyCode = nil
        scrollingKey = nil
        scroll("cancel()")
        lookupID = UUID()
        lookupTask?.cancel()
        lookupTask = nil
        audioTask?.cancel()
        audioTask = nil
        player?.stop()
        player = nil
        activeNavigation = nil
        webView.stopLoading()
        resourceHandler.stop()
    }

    func dismiss() {
        stop()
        onDismiss?()
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyUp, event.keyCode == scrollingKeyCode {
            endKeyboardScroll()
            return true
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            pendingG = false
            endKeyboardScroll()
            return false
        }
        let key = event.charactersIgnoringModifiers ?? ""
        let navigationKeys = ["j", "k", "h", "l", "d", "u", "f", "b", " ", "g", "G", "\u{1b}"]
        if event.type == .keyUp {
            return navigationKeys.contains(key)
        }
        guard event.type == .keyDown else { return false }
        if ["j", "k", "h", "l"].contains(key) {
            pendingG = false
            guard !event.isARepeat, scrollingKey != key else { return true }
            scrollingKeyCode = event.keyCode
            scrollingKey = key
            let x = key == "h" ? -1 : key == "l" ? 1 : 0
            let y = key == "k" ? -1 : key == "j" ? 1 : 0
            scroll("start(\(x),\(y))")
            return true
        }
        endKeyboardScroll()
        let script: String
        switch key {
        case "d": script = "by(0,window.innerHeight/2)"
        case "u": script = "by(0,-window.innerHeight/2)"
        case "f", " ": script = "by(0,window.innerHeight)"
        case "b": script = "by(0,-window.innerHeight)"
        case "g":
            guard !event.isARepeat else { return true }
            guard pendingG else { pendingG = true; return true }
            script = "edge(false)"
        case "G":
            guard !event.isARepeat else { pendingG = false; return true }
            script = "edge(true)"
        case "\u{1b}":
            pendingG = false
            if !event.isARepeat { dismiss() }
            return true
        default:
            pendingG = false
            return false
        }
        pendingG = false
        scroll(script)
        return true
    }

    private func endKeyboardScroll() {
        guard scrollingKeyCode != nil else { return }
        scrollingKeyCode = nil
        scrollingKey = nil
        scroll("end()")
    }

    private func scroll(_ action: String) {
        webView.evaluateJavaScript("window.vellumDictionaryScroll?.\(action);null;", in: nil, in: .defaultClient)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation, DictionaryPage.isEntryURL(webView.url, id: lookupID) else { return }
        presentEntry()
        autoPronounceIfNeeded(finishedLoading: true)
    }

    private func presentEntry() {
        model.isLoading = false
        model.message = nil
        if let anchor = pendingAnchor,
           let data = try? JSONSerialization.data(withJSONObject: [anchor]),
           let encoded = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("document.getElementById(\(encoded)[0])?.scrollIntoView();null;")
        }
        pendingAnchor = nil
    }

    private func autoPronounceIfNeeded(finishedLoading: Bool) {
        guard AppPreferences.automaticallyPronouncesDictionary(), !didAutoPronounce else { return }
        let id = lookupID
        webView.evaluateJavaScript(DictionaryPage.pronunciationScript) { [weak self] result, _ in
            guard let self, self.lookupID == id else { return }
            guard AppPreferences.automaticallyPronouncesDictionary(), !self.didAutoPronounce else { return }
            let links = result as? [String: String] ?? [:]
            guard finishedLoading || links[AppPreferences.dictionaryPronunciationAccent().rawValue] != nil else { return }
            self.didAutoPronounce = true
            self.pronounce(links: links)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if let link = DictionaryPage.link(url.absoluteString) {
            follow(link)
            decisionHandler(.cancel)
        } else if DictionaryPage.isEntryURL(url, id: lookupID) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "dictionary", message.frameInfo.isMainFrame,
              DictionaryPage.isEntryURL(message.frameInfo.request.url, id: lookupID) else { return }
        if let payload = message.body as? [String: Any], payload["type"] as? String == "layout",
           let height = payload["height"] as? Double, height.isFinite, height > 0 {
            let wasLoading = model.isLoading
            contentHeight = height
            updatePreferredHeight()
            presentEntry()
            if wasLoading { autoPronounceIfNeeded(finishedLoading: false) }
        } else if let raw = message.body as? String, let link = DictionaryPage.link(raw) {
            follow(link)
        }
    }

    private var language: AppUILanguage { AppUILanguage.saved() }

    private func follow(_ link: (kind: String, value: String, anchor: String?)) {
        if link.kind == "entry" {
            lookup(link.value, anchor: link.anchor)
        } else {
            play(link.value)
        }
    }

    private func pronounce(links: [String: String]) {
        let accent = AppPreferences.dictionaryPronunciationAccent()
        if let raw = links[accent.rawValue], let link = DictionaryPage.link(raw) {
            setAudioStatus(nil)
            play(link.value)
        } else {
            setAudioStatus(language.text(.dictionaryAudioUnavailable))
        }
    }

    private func play(_ path: String) {
        audioTask?.cancel()
        player?.stop()
        player = nil
        let id = lookupID
        let location = location
        audioTask = Task { [weak self] in
            do {
                guard let data = try await DictionaryStore.shared.resource(path, at: location) else {
                    throw URLError(.fileDoesNotExist)
                }
                guard !Task.isCancelled, let self, self.lookupID == id else { return }
                let player = try AVAudioPlayer(data: data)
                self.player = player
                guard player.play() else { throw URLError(.cannotDecodeContentData) }
            } catch {
                guard !Task.isCancelled, let self, self.lookupID == id else { return }
                self.setAudioStatus(self.language.text(.dictionaryAudioUnavailable))
            }
        }
    }

    private func navigationFailed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        showMessage(language.text(.dictionaryDamaged))
    }

    private func showMessage(_ message: String) {
        model.isLoading = false
        model.message = message
        contentHeight = nil
        updatePreferredHeight()
    }

    private func setAudioStatus(_ status: String?) {
        model.audioStatus = status
        updatePreferredHeight()
    }

    private func updatePreferredHeight() {
        let height = contentHeight.map { max(100, ceil($0) + 43 + (model.audioStatus == nil ? 0 : 24)) } ?? 160
        guard abs(height - preferredHeight) > 0.5 else { return }
        preferredHeight = height
        onPreferredHeightChange?(height)
    }

    private func message(for error: Error) -> String {
        switch error as? DictionaryError {
        case .dictionaryNotFound, .unreadableFile: language.text(.dictionaryUnavailable)
        case .unsupportedVersion, .encryptedArchive, .unsupportedEncoding, .unsupportedCompression: language.text(.dictionaryUnsupportedFormat)
        default: language.text(.dictionaryDamaged)
        }
    }
}

@MainActor
private final class DictionaryPopoverModel: ObservableObject {
    @Published var word = ""
    @Published var message: String?
    @Published var audioStatus: String?
    @Published var isLoading = false
    var onDismiss: (() -> Void)?
}

private struct DictionaryPopoverSurface: View {
    @ObservedObject var model: DictionaryPopoverModel
    let webView: WKWebView
    private var language: AppUILanguage { AppUILanguage.saved() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(model.word.isEmpty ? language.text(.dictionaryTitle) : model.word)
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button { model.onDismiss?() } label: { Image(systemName: "xmark") }
                    .buttonStyle(DictionaryToolbarButtonStyle())
                    .help(language.text(.dictionaryClose)).accessibilityLabel(language.text(.dictionaryClose))
            }
            .padding(.horizontal, 10).frame(height: 42)
            VellumDivider(axis: .horizontal).frame(height: 1)
            if let status = model.audioStatus {
                Text(status).font(.system(size: 11)).foregroundStyle(VellumColors.mutedColor)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 5)
            }
            ZStack {
                DictionaryWebContent(webView: webView)
                if let message = model.message {
                    VStack(spacing: 12) {
                        if model.isLoading { ProgressView().controlSize(.small) }
                        Text(message).font(.system(size: 13)).foregroundStyle(VellumColors.mutedColor)
                            .multilineTextAlignment(.center).textSelection(.enabled)
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VellumColors.panelColor)
                }
            }
        }
        .foregroundStyle(VellumColors.foregroundColor)
        .background(VellumColors.panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(VellumColors.borderColor, lineWidth: 1).allowsHitTesting(false) }
        .environment(\.colorScheme, .dark)
    }
}

private struct DictionaryWebContent: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct DictionaryToolbarButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 22, minHeight: 26).padding(.horizontal, 4)
            .foregroundStyle(hovering ? VellumColors.blueColor : VellumColors.mutedColor)
            .background(hovering || configuration.isPressed ? VellumColors.panelElevatedColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}

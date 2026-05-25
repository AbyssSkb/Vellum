@preconcurrency import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit



private enum AIExplanationPopoverMetrics {
    static let width: CGFloat = 520
    static let hoverMinimumHeight: CGFloat = 56
    static let minimumHeight: CGFloat = 124
    static let streamingMinimumHeight: CGFloat = 56
    static let maximumHeight: CGFloat = 420
    static let compactInitialHeight: CGFloat = 148
    static let standardInitialHeight: CGFloat = 260

    static func estimatedHeight(for markdown: String) -> CGFloat {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return minimumHeight }

        let lines = trimmed.components(separatedBy: .newlines)
        var headingCount = 0
        var paragraphCount = 0
        var listItemCount = 0
        var blankLineCount = 0
        let estimatedLineCount = lines.reduce(0) { partialResult, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                blankLineCount += 1
                return partialResult
            }

            if line.hasPrefix("#") {
                headingCount += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                listItemCount += 1
            } else {
                paragraphCount += 1
            }

            let characterCount = max(1, line.count)
            return partialResult + max(1, Int(ceil(Double(characterCount) / 56.0)))
        }

        let contentHeight = CGFloat(estimatedLineCount) * 21
            + CGFloat(headingCount) * 12
            + CGFloat(paragraphCount) * 6
            + CGFloat(listItemCount) * 3
            + CGFloat(blankLineCount) * 4
            + 46
        return min(maximumHeight, max(minimumHeight, contentHeight))
    }

    static func estimatedHoverHeight(for markdown: String) -> CGFloat {
        let lines = markdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return hoverMinimumHeight }

        let contentHeight = lines.enumerated().reduce(CGFloat(36)) { partialResult, element in
            let (index, line) = element
            let estimatedLineCount = max(1, Int(ceil(Double(max(1, line.count)) / 58.0)))
            let lineHeight: CGFloat = line.hasPrefix("#") ? 22 : 20
            let spacing: CGFloat = index == lines.count - 1 ? 0 : 9
            return partialResult + CGFloat(estimatedLineCount) * lineHeight + spacing
        }

        return min(maximumHeight, max(hoverMinimumHeight, ceil(contentHeight)))
    }
}

@MainActor
final class AIExplanationPopoverModel: ObservableObject {
    @Published var title: String
    @Published var text: String
    @Published var isStreaming: Bool
    @Published private(set) var preferredHeight: CGFloat
    let maximumHeight: CGFloat

    init(
        title: String,
        text: String = "",
        isStreaming: Bool = false,
        initialHeight: CGFloat = AIExplanationPopoverMetrics.standardInitialHeight,
        maximumHeight: CGFloat = AIExplanationPopoverMetrics.maximumHeight
    ) {
        self.title = title
        self.text = text
        self.isStreaming = isStreaming
        self.preferredHeight = initialHeight
        self.maximumHeight = maximumHeight
    }

    func append(_ chunk: String) {
        if text == "..." {
            text = ""
        }
        text += chunk
    }

    var preferredSize: NSSize {
        NSSize(width: AIExplanationPopoverMetrics.width, height: preferredHeight)
    }

    @discardableResult
    func updateContentHeight(
        _ contentHeight: CGFloat,
        minimumHeight: CGFloat = AIExplanationPopoverMetrics.minimumHeight
    ) -> Bool {
        let clampedHeight = min(
            maximumHeight,
            max(minimumHeight, ceil(contentHeight))
        )

        guard abs(preferredHeight - clampedHeight) > 8 else { return false }
        preferredHeight = clampedHeight
        return true
    }
}

struct AIExplanationPopoverView: View {
    @ObservedObject var model: AIExplanationPopoverModel
    let kind: AIExplanationPopoverKind
    let onDismiss: () -> Void
    let onHighlight: () -> Void
    let onCycleColor: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let onWebViewReady: (AIExplanationWebView) -> Void

    var body: some View {
        MarkdownWebView(
            markdown: model.text.isEmpty ? "..." : model.text,
            onDismiss: onDismiss,
            onHighlight: onHighlight,
            onCycleColor: onCycleColor,
            onContentHeightChange: onContentHeightChange,
            focusWhenReady: kind.shouldFocusWebView,
            autoScrollOnUpdate: kind.autoScrollOnUpdate,
            onReady: onWebViewReady
        )
        .frame(width: model.preferredSize.width, height: model.preferredSize.height)
        .background(TokyoNight.panelElevatedColor)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let onDismiss: () -> Void
    let onHighlight: () -> Void
    let onCycleColor: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let focusWhenReady: Bool
    let autoScrollOnUpdate: Bool
    let onReady: (AIExplanationWebView) -> Void

    func makeNSView(context: Context) -> AIExplanationWebView {
        let webView = AIExplanationWebView()
        webView.onDismiss = onDismiss
        webView.onHighlight = onHighlight
        webView.onCycleColor = onCycleColor
        webView.onContentHeightChange = onContentHeightChange
        webView.shouldFocusWhenReady = focusWhenReady
        webView.autoScrollOnUpdate = autoScrollOnUpdate
        onReady(webView)
        webView.render(markdown)
        return webView
    }

    func updateNSView(_ webView: AIExplanationWebView, context: Context) {
        webView.onDismiss = onDismiss
        webView.onHighlight = onHighlight
        webView.onCycleColor = onCycleColor
        webView.onContentHeightChange = onContentHeightChange
        webView.shouldFocusWhenReady = focusWhenReady
        webView.autoScrollOnUpdate = autoScrollOnUpdate
        onReady(webView)
        webView.render(markdown)

        guard focusWhenReady else { return }

        DispatchQueue.main.async { [weak webView] in
            guard let webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
    }
}

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
        loadHTMLString(Self.html, baseURL: nil)
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

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <script>
        window.MathJax = {
          tex: { inlineMath: [['$', '$'], ['\\\\(', '\\\\)']], displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']] },
          options: { skipHtmlTags: ['script','noscript','style','textarea','pre','code'] }
        };
      </script>
      <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
      <style>
        :root { color-scheme: dark; }
        html, body {
          margin: 0;
          padding: 0;
          background: #292E42;
          color: #C0CAF5;
          font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          line-height: 1.55;
          overflow-y: auto;
          scrollbar-width: none;
        }
        html::-webkit-scrollbar,
        body::-webkit-scrollbar,
        *::-webkit-scrollbar {
          width: 0;
          height: 0;
          display: none;
        }
        body { padding: 0 14px; box-sizing: border-box; }
        #content {
          padding: 18px 0;
          box-sizing: border-box;
        }
        #content > :first-child { margin-top: 0; }
        #content > :last-child { margin-bottom: 0; }
        h1, h2, h3 { color: #E0E7FF; margin: 0.8em 0 0.35em; line-height: 1.25; }
        h1 { font-size: 18px; } h2 { font-size: 16px; } h3 { font-size: 14px; }
        p { margin: 0 0 0.75em; }
        ul, ol { margin: 0 0 0.85em 1.25em; padding: 0; }
        li { margin: 0.2em 0; }
        blockquote {
          margin: 0.7em 0;
          padding: 0.2em 0 0.2em 0.8em;
          border-left: 3px solid #7AA2F7;
          color: #A9B1D6;
        }
        code {
          background: #1A1B26;
          color: #7DCFFF;
          padding: 1px 4px;
          border-radius: 4px;
          font-family: "SF Mono", Menlo, monospace;
          font-size: 12px;
        }
        pre {
          background: #1A1B26;
          border: 1px solid #3B4261;
          border-radius: 7px;
          padding: 10px;
          overflow-x: auto;
          scrollbar-width: none;
        }
        pre code { background: transparent; padding: 0; }
        strong { color: #E0E7FF; }
        a { color: #7AA2F7; }
        .empty { color: #565F89; }
      </style>
    </head>
    <body>
      <main id="content" class="empty">...</main>
      <script>
        const scrollState = {
          direction: 0,
          frame: null,
          lastTime: 0,
          velocity: 672
        };
        function tickScroll(now) {
          if (!scrollState.direction) { return; }
          const previous = scrollState.lastTime || now;
          const deltaSeconds = Math.min(0.05, Math.max(0, (now - previous) / 1000));
          scrollState.lastTime = now;
          window.scrollBy(0, scrollState.direction * scrollState.velocity * deltaSeconds);
          scrollState.frame = requestAnimationFrame(tickScroll);
        }
        window.vimpdfStartScroll = function(direction) {
          direction = direction < 0 ? -1 : 1;
          if (scrollState.direction === direction && scrollState.frame !== null) { return; }
          window.vimpdfStopScroll();
          scrollState.direction = direction;
          scrollState.lastTime = performance.now();
          window.scrollBy(0, direction * 28);
          scrollState.frame = requestAnimationFrame(tickScroll);
        };
        window.vimpdfStopScroll = function() {
          scrollState.direction = 0;
          scrollState.lastTime = 0;
          if (scrollState.frame !== null) {
            cancelAnimationFrame(scrollState.frame);
            scrollState.frame = null;
          }
        };
        window.vimpdfPulseScroll = function(direction) {
          direction = direction < 0 ? -1 : 1;
          window.scrollBy(0, direction * 28);
        };
        function escapeHTML(value) {
          return value.replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
        }
        function inlineMarkdown(value) {
          return value
            .replace(/`([^`]+)`/g, '<code>$1</code>')
            .replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>')
            .replace(/\\*([^*]+)\\*/g, '<em>$1</em>')
            .replace(/\\[([^\\]]+)\\]\\(([^\\)]+)\\)/g, '<a href="$2">$1</a>');
        }
        function renderMarkdown(markdown) {
          const fenceMap = [];
          let text = escapeHTML(markdown || '...');
          text = text.replace(/```([\\s\\S]*?)```/g, (_, code) => {
            const token = `@@CODE_${fenceMap.length}@@`;
            fenceMap.push(`<pre><code>${code.trim()}</code></pre>`);
            return token;
          });
          const lines = text.split(/\\n/);
          let html = '';
          let list = null;
          function closeList() {
            if (list) { html += `</${list}>`; list = null; }
          }
          for (const raw of lines) {
            const line = raw.trim();
            if (!line) { closeList(); continue; }
            let match;
            if ((match = line.match(/^(#{1,3})\\s+(.+)$/))) {
              closeList();
              html += `<h${match[1].length}>${inlineMarkdown(match[2])}</h${match[1].length}>`;
            } else if ((match = line.match(/^[-*]\\s+(.+)$/))) {
              if (list !== 'ul') { closeList(); html += '<ul>'; list = 'ul'; }
              html += `<li>${inlineMarkdown(match[1])}</li>`;
            } else if ((match = line.match(/^\\d+\\.\\s+(.+)$/))) {
              if (list !== 'ol') { closeList(); html += '<ol>'; list = 'ol'; }
              html += `<li>${inlineMarkdown(match[1])}</li>`;
            } else if ((match = line.match(/^&gt;\\s*(.+)$/))) {
              closeList();
              html += `<blockquote>${inlineMarkdown(match[1])}</blockquote>`;
            } else {
              closeList();
              html += `<p>${inlineMarkdown(line)}</p>`;
            }
          }
          closeList();
          for (let i = 0; i < fenceMap.length; i++) {
            html = html.replace(`@@CODE_${i}@@`, fenceMap[i]);
          }
          return html;
        }
        window.vimpdfSetMarkdown = function(markdown, followBottom) {
          const content = document.getElementById('content');
          content.className = markdown && markdown.trim() ? '' : 'empty';
          content.innerHTML = renderMarkdown(markdown);
          requestAnimationFrame(() => afterRender(followBottom));
          if (window.MathJax && window.MathJax.typesetPromise) {
            window.MathJax.typesetPromise([content])
              .then(() => { afterRender(followBottom); })
              .catch(() => { afterRender(followBottom); });
          }
        };
        function afterRender(followBottom) {
          reportContentHeight();
          if (followBottom && isContentOverflowing()) {
            scrollToBottom();
            requestAnimationFrame(scrollToBottom);
          }
        }
        function isContentOverflowing() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          return height - window.innerHeight > 8;
        }
        function scrollToTop() {
          window.scrollTo(0, 0);
        }
        function scrollToBottom() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          const maxScroll = Math.max(0, height - window.innerHeight);
          window.scrollTo(0, maxScroll <= 8 ? 0 : maxScroll);
        }
        window.vimpdfScrollToTop = function() {
          scrollToTop();
          requestAnimationFrame(scrollToTop);
        };
        window.vimpdfScrollToBottom = function() {
          scrollToBottom();
          requestAnimationFrame(scrollToBottom);
        };
        function postVimPDFCommand(command) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimpdf) {
            window.webkit.messageHandlers.vimpdf.postMessage(command);
          }
        }
        function postVimPDFMessage(message) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimpdf) {
            window.webkit.messageHandlers.vimpdf.postMessage(message);
          }
        }
        function reportContentHeight() {
          const content = document.getElementById('content');
          const bodyStyle = window.getComputedStyle(document.body);
          const paddingTop = parseFloat(bodyStyle.paddingTop) || 0;
          const paddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
          const contentHeight = content ? content.getBoundingClientRect().height : 0;
          const height = contentHeight + paddingTop + paddingBottom;
          postVimPDFMessage({ command: 'contentHeight', height: Math.ceil(height) });
        }
        document.addEventListener('keydown', function(event) {
          if (event.metaKey || event.ctrlKey || event.altKey) { return; }

          if (event.key === 'j') {
            event.preventDefault();
            postVimPDFCommand('startScrollDown');
          } else if (event.key === 'k') {
            event.preventDefault();
            postVimPDFCommand('startScrollUp');
          } else if (event.key === 'm') {
            event.preventDefault();
            postVimPDFCommand('highlight');
          } else if (event.key === 'c') {
            event.preventDefault();
            postVimPDFCommand('cycleColor');
          } else if (event.key === 'Escape') {
            event.preventDefault();
            postVimPDFCommand('dismiss');
          }
        }, true);
        document.addEventListener('keyup', function(event) {
          if (event.metaKey || event.ctrlKey || event.altKey) { return; }

          if (event.key === 'j' || event.key === 'k') {
            event.preventDefault();
            postVimPDFCommand('stopScroll');
          }
        }, true);
        window.addEventListener('blur', function() {
          postVimPDFCommand('stopScroll');
        });
        window.addEventListener('resize', reportContentHeight);
      </script>
    </body>
    </html>
    """
}



extension NSColor {
    func persistentHighlightColor() -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return withAlphaComponent(1)
        }

        let sourceOpacity: CGFloat = 0.42
        return NSColor(
            calibratedRed: rgb.redComponent * sourceOpacity + (1 - sourceOpacity),
            green: rgb.greenComponent * sourceOpacity + (1 - sourceOpacity),
            blue: rgb.blueComponent * sourceOpacity + (1 - sourceOpacity),
            alpha: 1
        )
    }
}

enum AIExplanationPopoverKind {
    case hover
    case message
    case streaming

    var behavior: NSPopover.Behavior {
        switch self {
        case .hover:
            return .applicationDefined
        case .message, .streaming:
            return .transient
        }
    }

    var animates: Bool {
        switch self {
        case .hover, .message, .streaming:
            return true
        }
    }

    var shouldFocusWebView: Bool {
        switch self {
        case .hover:
            return false
        case .message, .streaming:
            return true
        }
    }

    var allowsDynamicHeight: Bool {
        switch self {
        case .hover, .message, .streaming:
            return true
        }
    }

    var autoScrollOnUpdate: Bool {
        switch self {
        case .hover, .message, .streaming:
            return false
        }
    }
}

struct PDFReader: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
    let tabID: PDFTab.ID
    let document: PDFDocument
    let snapshot: ReaderSnapshot?
    let isActive: Bool

    func makeNSView(context: Context) -> VimPDFView {
        let view = VimPDFView()
        view.appState = appState
        view.saveBeforeDismantle = { [weak appState, weak view] in
            guard let snapshot = view?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }
        view.backgroundColor = TokyoNight.background
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        view.restore(snapshot)
        appState.setActivePDFView(view, for: tabID)
        if isActive, !appState.isOutlineVisible {
            view.focus()
        }
        return view
    }

    func updateNSView(_ nsView: VimPDFView, context: Context) {
        nsView.appState = appState
        nsView.saveBeforeDismantle = { [weak appState, weak nsView] in
            guard let snapshot = nsView?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }

        if nsView.document !== document {
            nsView.document = document
            nsView.restore(snapshot)
        }

        appState.setActivePDFView(nsView, for: tabID)
        if isActive, !appState.isOutlineVisible {
            DispatchQueue.main.async {
                nsView.focus()
            }
        }
    }

    static func dismantleNSView(_ nsView: VimPDFView, coordinator: ()) {
        nsView.saveBeforeDismantle?()
    }
}

private struct VimTextSelectionNavigationState {
    var anchorOffset: Int
    var extentOffset: Int
    var preferredX: CGFloat?
    var anchorCaret: VimTextCaret?
    var extentCaret: VimTextCaret?
}

private struct VimTextCaret {
    let offset: Int
    let pageIndex: Int
    let slotIndex: Int
    let point: NSPoint
    let lineMidY: CGFloat
}

private struct VimTextLineCharacter {
    let globalOffset: Int
    let minX: CGFloat
    let centerX: CGFloat
    let maxX: CGFloat
    let centerY: CGFloat
    let height: CGFloat
}

private struct VimTextLine {
    let pageIndex: Int
    let startOffset: Int
    let endOffset: Int
    let midY: CGFloat
    let characters: [VimTextLineCharacter]
}

private struct VimTextCaretPosition {
    let pageIndex: Int
    let lineIndex: Int
    let slotIndex: Int
}

private enum VimTextCharacterClass: Equatable {
    case whitespace
    case word
    case punctuation
}

final class VimPDFView: PDFView {
    private static let textSelectionNavigationKeys: Set<String> = ["h", "j", "k", "l", "w", "b", "e"]

    weak var appState: AppState?
    var saveBeforeDismantle: (() -> Void)?
    private var scrollTargetOrigin: NSPoint?
    private var scrollTimer: Timer?
    private var lastScrollTick = Date.timeIntervalSinceReferenceDate
    private var zoomTargetScale: CGFloat?
    private var zoomAnchor: PDFDestination?
    private var zoomTimer: Timer?
    private var lastZoomTick = Date.timeIntervalSinceReferenceDate
    private var jumpBackStack: [ReaderSnapshot] = []
    private var jumpForwardStack: [ReaderSnapshot] = []
    private var restoreGeneration = 0
    private var explanationTrackingArea: NSTrackingArea?
    private var explanationPopover: NSPopover?
    private var activeExplanationModel: AIExplanationPopoverModel?
    private var activeAISelection: PDFSelection?
    private var activeAIExistingAnnotations: [PDFAnnotation] = []
    private var activeAIExplanationTask: Task<Void, Never>?
    private weak var activeAIWebView: AIExplanationWebView?
    private var activeAIContinuousScrollKey: String?
    private var pendingPopoverContentHeight: CGFloat?
    private var popoverHeightUpdateWorkItem: DispatchWorkItem?
    private weak var hoveredExplanationAnnotation: PDFAnnotation?
    private var hoveredExplanationText: String?
    private var hoveredExplanationKey: String?
    private var suppressedHoverExplanationKey: String?
    private weak var suppressedHoverExplanationAnnotation: PDFAnnotation?
    private var suppressedHoverExplanationText: String?
    private var hoverPopoverHideWorkItem: DispatchWorkItem?
    private var isMouseSelectingText = false
    private var textSelectionNavigationState: VimTextSelectionNavigationState?

    override var acceptsFirstResponder: Bool { true }

    var isAIInteractionActive: Bool {
        explanationPopover?.isShown == true || activeExplanationModel != nil
    }

    var hasNavigableTextSelection: Bool {
        guard let selection = currentSelection else { return false }
        if selection.string?.isEmpty == false {
            return true
        }

        return selection.pages.contains { page in
            !selection.bounds(for: page).isEmpty
        }
    }

    var hasAnyTextSelection: Bool {
        currentSelection != nil
    }

    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let rawKey = event.charactersIgnoringModifiers,
              !rawKey.isEmpty else {
            return false
        }

        return handleTextSelectionKey(rawKey, eventType: event.type)
    }

    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool {
        let key = rawKey.lowercased()

        if key == "\u{1b}" {
            guard hasAnyTextSelection else { return false }
            if eventType == .keyDown {
                clearTextSelectionForVimNavigation()
            }
            return true
        }

        guard Self.textSelectionNavigationKeys.contains(key), hasNavigableTextSelection else { return false }

        switch eventType {
        case .keyDown:
            stopScrollAnimation()
            _ = vimNavigateTextSelection(key)
            return true
        case .keyUp:
            return true
        default:
            return false
        }
    }

    private func clearTextSelectionForVimNavigation() {
        stopScrollAnimation()
        textSelectionNavigationState = nil
        clearSelection()
        needsDisplay = true
        focus()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        configurePDFScrollers()
        updateExplanationTrackingArea()
        if appState?.isOutlineVisible != true {
            focus()
        }
        DispatchQueue.main.async { [weak self] in
            self?.configurePDFScrollers()
        }
    }

    override func layout() {
        super.layout()
        configurePDFScrollers()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateExplanationTrackingArea()
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }
        super.keyUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredAIExplanation(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        isMouseSelectingText = true
        textSelectionNavigationState = nil
        hideAIExplanationPopover()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        isMouseSelectingText = true
        hideAIExplanationPopover()
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.isMouseSelectingText = false
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredExplanationAnnotation != nil {
            scheduleHoverPopoverHide()
        }
    }

    private func updateExplanationTrackingArea() {
        if let explanationTrackingArea {
            removeTrackingArea(explanationTrackingArea)
            self.explanationTrackingArea = nil
        }

        guard window != nil else { return }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        explanationTrackingArea = trackingArea
    }

    private func configurePDFScrollers() {
        guard let scrollView = pdfScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .default
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
    }

    private func updateHoveredAIExplanation(for event: NSEvent) {
        if activeExplanationModel != nil, hoveredExplanationAnnotation == nil {
            return
        }

        if isMouseSelectingText || currentSelection != nil || NSEvent.pressedMouseButtons != 0 {
            hideAIExplanationPopover()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let annotation = aiExplanationAnnotation(at: point),
              let explanation = AIExplanationAnnotation.decode(annotation.contents) else {
            if let suppressedHoverExplanationAnnotation,
               let suppressedHoverExplanationText,
               isPoint(point, insideExplanationGroupFor: suppressedHoverExplanationAnnotation, explanation: suppressedHoverExplanationText) {
                hideAIExplanationPopover()
                return
            }

            if let hoveredExplanationAnnotation,
               let hoveredExplanationText,
               isPoint(point, insideExplanationGroupFor: hoveredExplanationAnnotation, explanation: hoveredExplanationText) {
                cancelPendingHoverPopoverHide()
                return
            }

            clearSuppressedHoverExplanation()
            scheduleHoverPopoverHide()
            return
        }
        let hoverKey = hoverExplanationKey(for: annotation, explanation: explanation)

        if suppressedHoverExplanationKey == hoverKey {
            hideAIExplanationPopover()
            return
        }
        clearSuppressedHoverExplanation()

        cancelPendingHoverPopoverHide()

        if hoveredExplanationKey == hoverKey,
           hoveredExplanationText == explanation,
           explanationPopover?.isShown == true {
            hoveredExplanationAnnotation = annotation
            return
        }

        showAIExplanationPopover(explanation, at: point, annotation: annotation, hoverKey: hoverKey)
    }

    private func aiExplanationAnnotation(at pointInView: NSPoint) -> PDFAnnotation? {
        guard let page = page(for: pointInView, nearest: false) else { return nil }

        let pointOnPage = convert(pointInView, to: page)
        return page.annotations.reversed().first { annotation in
            annotation.type == "Highlight"
                && AIExplanationAnnotation.decode(annotation.contents) != nil
                && highlightRegions(for: annotation).contains { region in
                    region.insetBy(dx: -2, dy: -2).contains(pointOnPage)
                }
        }
    }

    private func showAIExplanationPopover(
        _ explanation: String,
        at point: NSPoint,
        annotation: PDFAnnotation,
        hoverKey: String
    ) {
        let model = AIExplanationPopoverModel(
            title: "Saved explanation",
            text: explanation,
            initialHeight: AIExplanationPopoverMetrics.estimatedHoverHeight(for: explanation)
        )
        showPopover(
            model: model,
            at: explanationPopoverAnchorRect(for: annotation, explanation: explanation, fallbackPoint: point),
            kind: .hover
        )
        clearSuppressedHoverExplanation()
        hoveredExplanationAnnotation = annotation
        hoveredExplanationText = explanation
        hoveredExplanationKey = hoverKey
    }

    private func showAIMessage(_ message: String, at rect: NSRect? = nil) {
        let model = AIExplanationPopoverModel(
            title: "VimPDF",
            text: message,
            initialHeight: AIExplanationPopoverMetrics.compactInitialHeight
        )
        showPopover(model: model, at: rect ?? selectionPopoverRect(for: currentSelection), kind: .message)
        clearSuppressedHoverExplanation()
        hoveredExplanationAnnotation = nil
        hoveredExplanationText = message
        hoveredExplanationKey = nil
    }

    private func showStreamingAIExplanationPopover(
        title: String,
        at rect: NSRect?
    ) -> AIExplanationPopoverModel? {
        let model = AIExplanationPopoverModel(
            title: title,
            isStreaming: true,
            initialHeight: AIExplanationPopoverMetrics.streamingMinimumHeight
        )
        showPopover(model: model, at: rect ?? selectionPopoverRect(for: currentSelection), kind: .streaming)
        clearSuppressedHoverExplanation()
        hoveredExplanationAnnotation = nil
        hoveredExplanationText = nil
        hoveredExplanationKey = nil
        return model
    }

    private func showPopover(
        model: AIExplanationPopoverModel,
        at rect: NSRect?,
        kind: AIExplanationPopoverKind
    ) {
        guard window != nil else { return }
        cancelPendingHoverPopoverHide()
        hideAIExplanationPopover()

        let popover = NSPopover()
        popover.behavior = kind.behavior
        popover.animates = kind.animates
        popover.contentSize = model.preferredSize
        popover.contentViewController = NSHostingController(
            rootView: AIExplanationPopoverView(
                model: model,
                kind: kind,
                onDismiss: { [weak self] in
                    switch kind {
                    case .hover:
                        self?.dismissHoverAIExplanation(suppressCurrent: true)
                    case .message, .streaming:
                        self?.dismissActiveAIInteraction(clearSelection: true)
                    }
                },
                onHighlight: { [weak self] in
                    self?.highlightActiveAISelection()
                },
                onCycleColor: { [weak self] in
                    self?.appState?.cycleHighlightColor(preserveFocus: true)
                },
                onContentHeightChange: { [weak self, model, kind] contentHeight in
                    guard kind.allowsDynamicHeight else { return }

                    switch kind {
                    case .streaming:
                        self?.scheduleStreamingPopoverHeightUpdate(model: model, contentHeight: contentHeight)
                    case .message:
                        self?.applyPopoverHeight(model: model, contentHeight: contentHeight, scrollToBottom: false)
                    case .hover:
                        self?.applyPopoverHeight(
                            model: model,
                            contentHeight: contentHeight,
                            minimumHeight: AIExplanationPopoverMetrics.hoverMinimumHeight,
                            scrollToBottom: false
                        )
                    }
                },
                onWebViewReady: { [weak self, kind] webView in
                    self?.activeAIWebView = webView
                    guard kind.shouldFocusWebView else { return }

                    DispatchQueue.main.async { [weak webView] in
                        guard let webView else { return }
                        webView.window?.makeFirstResponder(webView)
                    }
                }
            )
        )

        let anchor = rect ?? NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        explanationPopover = popover
        activeExplanationModel = model
    }

    private func scheduleStreamingPopoverHeightUpdate(model: AIExplanationPopoverModel, contentHeight: CGFloat) {
        pendingPopoverContentHeight = contentHeight

        guard popoverHeightUpdateWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self, model] in
            guard let self else { return }

            let latestHeight = self.pendingPopoverContentHeight ?? contentHeight
            self.pendingPopoverContentHeight = nil
            self.popoverHeightUpdateWorkItem = nil
            self.applyPopoverHeight(
                model: model,
                contentHeight: latestHeight,
                minimumHeight: AIExplanationPopoverMetrics.streamingMinimumHeight,
                scrollToBottom: true
            )
        }
        popoverHeightUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045, execute: workItem)
    }

    private func applyPopoverHeight(
        model: AIExplanationPopoverModel,
        contentHeight: CGFloat,
        minimumHeight: CGFloat = AIExplanationPopoverMetrics.minimumHeight,
        scrollToBottom: Bool
    ) {
        guard activeExplanationModel === model else { return }

        if model.updateContentHeight(contentHeight, minimumHeight: minimumHeight) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                explanationPopover?.contentSize = model.preferredSize
            }
        }

        if scrollToBottom, let webView = activeAIWebView {
            let shouldStickToBottom = ceil(contentHeight) > model.maximumHeight + 1
            let alignScroll = { [weak webView] in
                if shouldStickToBottom {
                    webView?.scrollToBottom()
                } else {
                    webView?.scrollToTop()
                }
            }

            alignScroll()
            DispatchQueue.main.async {
                alignScroll()
            }
        }
    }

    private func hideAIExplanationPopover() {
        cancelPendingHoverPopoverHide()
        popoverHeightUpdateWorkItem?.cancel()
        popoverHeightUpdateWorkItem = nil
        pendingPopoverContentHeight = nil
        stopAIContinuousScroll()
        explanationPopover?.close()
        explanationPopover = nil
        activeExplanationModel = nil
        activeAIWebView = nil
        hoveredExplanationAnnotation = nil
        hoveredExplanationText = nil
        hoveredExplanationKey = nil
    }

    private func dismissHoverAIExplanation(suppressCurrent: Bool) {
        if suppressCurrent, let hoveredExplanationKey {
            suppressedHoverExplanationKey = hoveredExplanationKey
            suppressedHoverExplanationAnnotation = hoveredExplanationAnnotation
            suppressedHoverExplanationText = hoveredExplanationText
        }
        hideAIExplanationPopover()
        focus()
    }

    private func clearSuppressedHoverExplanation() {
        suppressedHoverExplanationKey = nil
        suppressedHoverExplanationAnnotation = nil
        suppressedHoverExplanationText = nil
    }

    private func explanationPopoverAnchorRect(
        for annotation: PDFAnnotation,
        explanation: String,
        fallbackPoint: NSPoint
    ) -> NSRect {
        guard let page = annotation.page else {
            return NSRect(x: fallbackPoint.x, y: fallbackPoint.y, width: 1, height: 1)
        }

        let annotations = explanationAnnotations(matching: explanation, on: page)
        let sourceAnnotations = annotations.isEmpty ? [annotation] : annotations
        let points = sourceAnnotations.flatMap { annotation in
            highlightRegions(for: annotation).flatMap { region in
                [
                    NSPoint(x: region.minX, y: region.minY),
                    NSPoint(x: region.maxX, y: region.minY),
                    NSPoint(x: region.minX, y: region.maxY),
                    NSPoint(x: region.maxX, y: region.maxY)
                ]
            }
        }

        guard let pageRect = rect(containing: points) ?? rect(containing: [
            NSPoint(x: annotation.bounds.minX, y: annotation.bounds.minY),
            NSPoint(x: annotation.bounds.maxX, y: annotation.bounds.maxY)
        ]),
              let viewRect = viewRect(for: pageRect, on: page) else {
            return NSRect(x: fallbackPoint.x, y: fallbackPoint.y, width: 1, height: 1)
        }

        return viewRect.insetBy(dx: -3, dy: -3)
    }

    private func explanationAnnotations(matching explanation: String, on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && AIExplanationAnnotation.decode(annotation.contents) == explanation
        }
    }

    private func hoverExplanationKey(for annotation: PDFAnnotation, explanation: String) -> String {
        let pageIndex: Int
        if let page = annotation.page, let document {
            let index = document.index(for: page)
            pageIndex = index == NSNotFound ? -1 : index
        } else {
            pageIndex = -1
        }

        return "\(pageIndex):\(explanation)"
    }

    private func scheduleHoverPopoverHide() {
        guard hoveredExplanationAnnotation != nil else { return }

        hoverPopoverHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideHoverPopoverIfNeeded()
        }
        hoverPopoverHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: workItem)
    }

    private func hideHoverPopoverIfNeeded() {
        guard let hoveredExplanationKey else { return }

        if mouseIsHoveringExplanationGroup(hoveredExplanationKey)
            || mouseIsInsideExplanationPopover() {
            scheduleHoverPopoverHide()
            return
        }

        hideAIExplanationPopover()
    }

    private func cancelPendingHoverPopoverHide() {
        hoverPopoverHideWorkItem?.cancel()
        hoverPopoverHideWorkItem = nil
    }

    private func mouseIsInsideExplanationPopover() -> Bool {
        guard let popoverWindow = explanationPopover?.contentViewController?.view.window else {
            return false
        }

        return popoverWindow.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)
    }

    private func mouseIsHoveringExplanationGroup(_ hoverKey: String) -> Bool {
        guard let point = currentMousePointInView(),
              bounds.insetBy(dx: -4, dy: -4).contains(point) else { return false }

        if let annotation = aiExplanationAnnotation(at: point),
           let explanation = AIExplanationAnnotation.decode(annotation.contents) {
            return hoverExplanationKey(for: annotation, explanation: explanation) == hoverKey
        }

        guard let hoveredExplanationAnnotation,
              let hoveredExplanationText,
              hoveredExplanationKey == hoverKey else { return false }

        return isPoint(point, insideExplanationGroupFor: hoveredExplanationAnnotation, explanation: hoveredExplanationText)
    }

    private func isPoint(
        _ pointInView: NSPoint,
        insideExplanationGroupFor referenceAnnotation: PDFAnnotation,
        explanation: String
    ) -> Bool {
        guard let page = referenceAnnotation.page else { return false }

        let annotations = explanationAnnotations(matching: explanation, on: page)
        let sourceAnnotations = annotations.isEmpty ? [referenceAnnotation] : annotations
        let points = sourceAnnotations.flatMap { annotation in
            highlightRegions(for: annotation).flatMap { region in
                [
                    NSPoint(x: region.minX, y: region.minY),
                    NSPoint(x: region.maxX, y: region.minY),
                    NSPoint(x: region.minX, y: region.maxY),
                    NSPoint(x: region.maxX, y: region.maxY)
                ]
            }
        }

        guard let groupBounds = rect(containing: points) else { return false }
        let pointOnPage = convert(pointInView, to: page)
        return groupBounds.insetBy(dx: -5, dy: -8).contains(pointOnPage)
    }

    private func currentMousePointInView() -> NSPoint? {
        guard let window else { return nil }

        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(pointInWindow, from: nil)
    }

    func handleAIKeyEvent(_ event: NSEvent) -> Bool {
        guard isAIInteractionActive else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return false }

        switch event.type {
        case .keyDown:
            if key == "\u{1b}", hoveredExplanationKey != nil {
                dismissHoverAIExplanation(suppressCurrent: true)
                return true
            }

            if key == "j" || key == "k" {
                startAIContinuousScroll(key)
                return true
            }

            if activeAIWebView?.handleKey(key) == true {
                return true
            }
            return ["j", "k", "m", "c", "\u{1b}"].contains(key)
        case .keyUp:
            if key == "j" || key == "k" {
                if activeAIContinuousScrollKey == key {
                    stopAIContinuousScroll()
                }
                return true
            }
            return ["j", "k", "m", "c", "\u{1b}"].contains(key)
        default:
            return false
        }
    }

    private func startAIContinuousScroll(_ key: String) {
        guard activeAIContinuousScrollKey != key else { return }

        activeAIContinuousScrollKey = key
        activeAIWebView?.startContinuousScroll(direction: key == "j" ? 1 : -1)
    }

    private func stopAIContinuousScroll() {
        activeAIContinuousScrollKey = nil
        activeAIWebView?.stopContinuousScroll()
    }

    private func dismissActiveAIInteraction(clearSelection shouldClearSelection: Bool) {
        activeAIExplanationTask?.cancel()
        activeAIExplanationTask = nil
        activeAISelection = nil
        activeAIExistingAnnotations = []
        if shouldClearSelection {
            clearSelection()
            textSelectionNavigationState = nil
        }
        hideAIExplanationPopover()
        focus()
    }

    private func highlightActiveAISelection() {
        guard let selection = activeAISelection ?? currentSelection else {
            dismissActiveAIInteraction(clearSelection: true)
            return
        }

        activeAIExplanationTask?.cancel()
        activeAIExplanationTask = nil

        let color = appState?.selectedHighlightColor.annotationColor ?? HighlightColor.yellow.annotationColor
        let annotations = addHighlightAnnotations(for: selection, color: color)
        let explanation = activeExplanationModel?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        if let explanation {
            for annotation in annotations {
                annotation.contents = AIExplanationAnnotation.encode(explanation)
                annotation.userName = "VimPDF AI"
                annotation.modificationDate = Date()
            }
        }

        needsDisplay = true
        persistAnnotationsIfPossible()
        dismissActiveAIInteraction(clearSelection: true)
    }

    private func selectionPopoverRect(for selection: PDFSelection?) -> NSRect? {
        guard let selection else { return nil }

        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = tightHighlightBounds(for: lineSelection, on: page),
                      let viewRect = viewRect(for: bounds, on: page) else { continue }
                return viewRect
            }
        }

        return nil
    }

    private func viewRect(for pageRect: NSRect, on page: PDFPage) -> NSRect? {
        rect(containing: [
            convert(NSPoint(x: pageRect.minX, y: pageRect.minY), from: page),
            convert(NSPoint(x: pageRect.maxX, y: pageRect.minY), from: page),
            convert(NSPoint(x: pageRect.minX, y: pageRect.maxY), from: page),
            convert(NSPoint(x: pageRect.maxX, y: pageRect.maxY), from: page)
        ])
    }

    @discardableResult
    func vimNavigateTextSelection(_ key: String) -> Bool {
        let key = key.lowercased()
        guard ["h", "j", "k", "l", "w", "b", "e"].contains(key),
              let document,
              hasNavigableTextSelection else {
            return false
        }

        let pageStarts = textPageStarts(in: document)
        guard let totalLength = pageStarts.last, totalLength > 0 else { return false }

        if textSelectionNavigationState == nil {
            guard let range = currentSelectionCharacterRange(pageStarts: pageStarts) else { return false }
            textSelectionNavigationState = VimTextSelectionNavigationState(
                anchorOffset: range.start,
                extentOffset: range.end,
                preferredX: nil,
                anchorCaret: textCaret(
                    atInsertionOffset: range.start,
                    preferTrailingEdge: false,
                    pageStarts: pageStarts
                ),
                extentCaret: textCaret(
                    atInsertionOffset: range.end,
                    preferTrailingEdge: true,
                    pageStarts: pageStarts
                )
            )
        }

        guard var state = textSelectionNavigationState else { return false }
        var nextExtent: Int?
        var nextExtentCaret: VimTextCaret?
        var movementDirection = 0
        var scrollCaretAfterSelection: VimTextCaret?
        var useVisualSelection = false

        switch key {
        case "h":
            nextExtent = state.extentOffset - 1
            movementDirection = -1
            state.preferredX = nil
        case "l":
            nextExtent = state.extentOffset + 1
            movementDirection = 1
            state.preferredX = nil
        case "b":
            nextExtent = wordBackwardOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
            movementDirection = -1
            state.preferredX = nil
        case "w":
            nextExtent = wordForwardOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
            movementDirection = 1
            state.preferredX = nil
        case "e":
            nextExtent = wordEndOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
            movementDirection = 1
            state.preferredX = nil
        case "j", "k":
            useVisualSelection = true
            let verticalMove = verticalSelectionCaret(
                from: state.extentCaret,
                fallbackExtentOffset: state.extentOffset,
                anchorOffset: state.anchorOffset,
                anchorCaret: state.anchorCaret,
                direction: key == "j" ? 1 : -1,
                preferredX: state.preferredX,
                pageStarts: pageStarts
            )
            nextExtent = verticalMove?.caret.offset
            nextExtentCaret = verticalMove?.caret
            scrollCaretAfterSelection = verticalMove?.caret
            state.preferredX = verticalMove?.preferredX ?? state.preferredX
            movementDirection = key == "j" ? 1 : -1
        default:
            return false
        }

        guard var extent = nextExtent else { return false }
        extent = min(max(extent, 0), totalLength)
        if !useVisualSelection, extent == state.anchorOffset {
            extent = min(max(state.anchorOffset + movementDirection, 0), totalLength)
        }
        if useVisualSelection {
            guard nextExtentCaret != nil,
                  !sameVisualCaret(nextExtentCaret, state.anchorCaret) else { return true }
        } else {
            guard extent != state.anchorOffset else { return true }
        }

        state.extentOffset = extent
        state.extentCaret = nextExtentCaret ?? textCaret(
            atInsertionOffset: state.extentOffset,
            preferTrailingEdge: state.extentOffset >= state.anchorOffset,
            pageStarts: pageStarts
        )

        let didApplySelection = useVisualSelection
            ? applyVisualTextSelection(anchorCaret: state.anchorCaret, extentCaret: state.extentCaret, pageStarts: pageStarts)
                || applyTextSelection(
                    anchorOffset: state.anchorOffset,
                    extentOffset: state.extentOffset,
                    pageStarts: pageStarts,
                    scrollToEndpoint: scrollCaretAfterSelection == nil
                )
            : applyTextSelection(
                anchorOffset: state.anchorOffset,
                extentOffset: state.extentOffset,
                pageStarts: pageStarts,
                scrollToEndpoint: scrollCaretAfterSelection == nil
            )

        guard didApplySelection else {
            textSelectionNavigationState = nil
            return false
        }

        if let scrollCaretAfterSelection {
            scrollTextCaretToVisible(scrollCaretAfterSelection)
        }

        textSelectionNavigationState = state
        return true
    }

    private func currentSelectionCharacterRange(pageStarts: [Int]) -> (start: Int, end: Int)? {
        guard let selection = currentSelection else { return nil }

        var selectedRanges: [(start: Int, end: Int)] = []
        for page in selection.pages {
            guard let pageIndex = document?.index(for: page),
                  pageIndex != NSNotFound,
                  pageIndex + 1 < pageStarts.count else { continue }

            let pageStart = pageStarts[pageIndex]
            let rangeCount = selection.numberOfTextRanges(on: page)
            for rangeIndex in 0..<rangeCount {
                let range = selection.range(at: rangeIndex, on: page)
                guard range.location != NSNotFound, range.length > 0 else { continue }

                let start = pageStart + range.location
                let end = min(pageStarts[pageIndex + 1], start + range.length)
                guard end > start else { continue }
                selectedRanges.append((start, end))
            }
        }

        if let start = selectedRanges.map(\.start).min(),
           let end = selectedRanges.map(\.end).max(),
           end > start {
            return (start, end)
        }

        var selectedOffsets: [Int] = []
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var pageRects: [Int: [NSRect]] = [:]

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let pageIndex = document?.index(for: page),
                      pageIndex != NSNotFound,
                      pageIndex + 1 < pageStarts.count else { continue }

                let bounds = lineSelection.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                pageRects[pageIndex, default: []].append(bounds.insetBy(dx: -1.5, dy: -2.0))
            }
        }

        for (pageIndex, rects) in pageRects {
            guard let page = document?.page(at: pageIndex) else { continue }
            let pageStart = pageStarts[pageIndex]
            for characterIndex in 0..<page.numberOfCharacters {
                let bounds = page.characterBounds(at: characterIndex)
                guard bounds.width > 0, bounds.height > 0 else { continue }

                let center = NSPoint(x: bounds.midX, y: bounds.midY)
                if rects.contains(where: { rect in rect.contains(center) || rect.intersects(bounds) }) {
                    selectedOffsets.append(pageStart + characterIndex)
                }
            }
        }

        guard let start = selectedOffsets.min(),
              let end = selectedOffsets.max().map({ $0 + 1 }),
              end > start else {
            return selectionStringCharacterRange(selection, pageStarts: pageStarts)
        }

        return (start, end)
    }

    private func selectionStringCharacterRange(
        _ selection: PDFSelection,
        pageStarts: [Int]
    ) -> (start: Int, end: Int)? {
        guard let selectedText = selection.string?.nilIfEmpty else { return nil }

        for page in selection.pages {
            guard let pageIndex = document?.index(for: page),
                  pageIndex != NSNotFound,
                  pageIndex < pageStarts.count,
                  let pageText = page.string as NSString? else { continue }

            let range = pageText.range(of: selectedText)
            if range.location != NSNotFound, range.length > 0 {
                let start = pageStarts[pageIndex] + range.location
                return (start, start + range.length)
            }
        }

        guard let document else { return nil }
        let documentText = documentText(in: document) as NSString
        let range = documentText.range(of: selectedText)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return (range.location, range.location + range.length)
    }

    private func applyTextSelection(
        anchorOffset: Int,
        extentOffset: Int,
        pageStarts: [Int],
        scrollToEndpoint: Bool = true
    ) -> Bool {
        guard let document else { return false }

        let startOffset = min(anchorOffset, extentOffset)
        let endOffset = max(anchorOffset, extentOffset)
        guard endOffset > startOffset else { return false }

        if let startEndpoint = textSelectionEndpoint(forInclusiveOffset: startOffset, pageStarts: pageStarts),
           let endEndpoint = textSelectionEndpoint(forInclusiveOffset: endOffset - 1, pageStarts: pageStarts),
           let selection = document.selection(
                from: startEndpoint.page,
                atCharacterIndex: startEndpoint.characterIndex,
                to: endEndpoint.page,
                atCharacterIndex: endEndpoint.characterIndex
           ),
           !selection.pages.isEmpty {
            setCurrentSelection(selection, animate: false)
            if scrollToEndpoint {
                scrollTextSelectionEndpointToVisible(
                    anchorOffset: anchorOffset,
                    extentOffset: extentOffset,
                    pageStarts: pageStarts
                )
            }
            needsDisplay = true
            return true
        }

        let selection = PDFSelection()
        for pageIndex in 0..<document.pageCount {
            guard pageIndex + 1 < pageStarts.count,
                  let page = document.page(at: pageIndex) else { continue }

            let pageStart = pageStarts[pageIndex]
            let pageEnd = pageStarts[pageIndex + 1]
            let localStart = max(startOffset, pageStart) - pageStart
            let localEnd = min(endOffset, pageEnd) - pageStart
            guard localEnd > localStart else { continue }

            let range = NSRange(location: localStart, length: localEnd - localStart)
            if let pageSelection = page.selection(for: range) {
                selection.add(pageSelection)
            }
        }

        guard !selection.pages.isEmpty else { return false }
        setCurrentSelection(selection, animate: false)
        if scrollToEndpoint {
            scrollTextSelectionEndpointToVisible(
                anchorOffset: anchorOffset,
                extentOffset: extentOffset,
                pageStarts: pageStarts
            )
        }
        needsDisplay = true
        return true
    }

    private func applyVisualTextSelection(
        anchorCaret: VimTextCaret?,
        extentCaret: VimTextCaret?,
        pageStarts: [Int]
    ) -> Bool {
        guard let anchorCaret,
              let extentCaret,
              let document else { return false }

        let anchorPosition = visualCaretPosition(for: anchorCaret, pageStarts: pageStarts)
        let extentPosition = visualCaretPosition(for: extentCaret, pageStarts: pageStarts)
        guard let anchorPosition, let extentPosition else { return false }

        let isForward = compareVisualPosition(anchorPosition, extentPosition) <= 0
        let start = isForward ? anchorPosition : extentPosition
        let end = isForward ? extentPosition : anchorPosition

        let selection = PDFSelection()
        for pageIndex in start.pageIndex...end.pageIndex {
            guard pageIndex + 1 < pageStarts.count,
                  let page = document.page(at: pageIndex) else { continue }

            let lines = textLines(onPageAt: pageIndex, pageStarts: pageStarts)
            guard !lines.isEmpty else { continue }

            let firstLine = pageIndex == start.pageIndex ? start.lineIndex : 0
            let lastLine = pageIndex == end.pageIndex ? end.lineIndex : lines.count - 1
            guard firstLine <= lastLine,
                  firstLine >= 0,
                  lastLine < lines.count else { continue }

            for lineIndex in firstLine...lastLine {
                let line = lines[lineIndex]
                let startSlot = pageIndex == start.pageIndex && lineIndex == start.lineIndex
                    ? start.slotIndex
                    : 0
                let endSlot = pageIndex == end.pageIndex && lineIndex == end.lineIndex
                    ? end.slotIndex
                    : line.characters.count

                addVisualLineSelection(
                    line: line,
                    startSlot: startSlot,
                    endSlot: endSlot,
                    page: page,
                    pageStart: pageStarts[pageIndex],
                    to: selection
                )
            }
        }

        guard !selection.pages.isEmpty else { return false }
        setCurrentSelection(selection, animate: false)
        scrollTextCaretToVisible(extentCaret)
        needsDisplay = true
        return true
    }

    private func addVisualLineSelection(
        line: VimTextLine,
        startSlot rawStartSlot: Int,
        endSlot rawEndSlot: Int,
        page: PDFPage,
        pageStart: Int,
        to selection: PDFSelection
    ) {
        let startSlot = min(max(rawStartSlot, 0), line.characters.count)
        let endSlot = min(max(rawEndSlot, 0), line.characters.count)
        guard endSlot > startSlot else { return }

        let offsets = line.characters[startSlot..<endSlot]
            .map { $0.globalOffset - pageStart }
            .sorted()
        guard var runStart = offsets.first else { return }
        var previous = runStart

        for offset in offsets.dropFirst() {
            if offset == previous + 1 {
                previous = offset
                continue
            }

            addPageSelection(page: page, start: runStart, end: previous + 1, to: selection)
            runStart = offset
            previous = offset
        }

        addPageSelection(page: page, start: runStart, end: previous + 1, to: selection)
    }

    private func addPageSelection(page: PDFPage, start: Int, end: Int, to selection: PDFSelection) {
        guard end > start else { return }

        let range = NSRange(location: start, length: end - start)
        if let pageSelection = page.selection(for: range) {
            selection.add(pageSelection)
        }
    }

    private func textSelectionEndpoint(
        forInclusiveOffset offset: Int,
        pageStarts: [Int]
    ) -> (page: PDFPage, characterIndex: Int)? {
        guard let document,
              let totalLength = pageStarts.last,
              totalLength > 0 else { return nil }

        let clampedOffset = min(max(offset, 0), totalLength - 1)
        guard let pageIndex = pageIndex(containing: clampedOffset, pageStarts: pageStarts),
              let page = document.page(at: pageIndex),
              page.numberOfCharacters > 0 else { return nil }

        let characterIndex = min(
            max(clampedOffset - pageStarts[pageIndex], 0),
            max(0, page.numberOfCharacters - 1)
        )
        return (page, characterIndex)
    }

    private func textCaret(
        atInsertionOffset offset: Int,
        preferTrailingEdge: Bool,
        pageStarts: [Int]
    ) -> VimTextCaret? {
        guard let totalLength = pageStarts.last, totalLength > 0 else { return nil }

        let insertionOffset = min(max(offset, 0), totalLength)
        let candidateOffset: Int
        let preferPrevious: Bool

        if preferTrailingEdge {
            candidateOffset = max(0, insertionOffset - 1)
            preferPrevious = true
        } else if insertionOffset >= totalLength {
            candidateOffset = totalLength - 1
            preferPrevious = true
        } else {
            candidateOffset = insertionOffset
            preferPrevious = false
        }

        guard let character = visibleTextCharacterWithLocation(
            near: candidateOffset,
            preferPrevious: preferPrevious,
            pageStarts: pageStarts
        ) else { return nil }

        let lines = textLines(onPageAt: character.pageIndex, pageStarts: pageStarts)
        guard let lineIndex = lines.firstIndex(where: { line in
            line.characters.contains { $0.globalOffset == character.globalOffset }
        }) else { return nil }

        let line = lines[lineIndex]
        let useTrailingEdge = preferTrailingEdge || insertionOffset >= totalLength
        let slotIndex = slotIndex(
            forInsertionOffset: insertionOffset,
            preferTrailingEdge: useTrailingEdge,
            in: line
        )
        let slotPoint = pointForSlot(slotIndex, in: line)

        return VimTextCaret(
            offset: insertionOffset,
            pageIndex: character.pageIndex,
            slotIndex: slotIndex,
            point: NSPoint(
                x: slotPoint.x,
                y: slotPoint.y
            ),
            lineMidY: line.midY
        )
    }

    private func visibleTextCharacterWithLocation(
        near offset: Int,
        preferPrevious: Bool,
        pageStarts: [Int]
    ) -> (pageIndex: Int, globalOffset: Int, bounds: NSRect)? {
        guard let totalLength = pageStarts.last, totalLength > 0 else { return nil }

        let clampedOffset = min(max(offset, 0), totalLength - 1)
        if preferPrevious {
            if let previous = visibleTextCharacterWithLocation(
                in: stride(from: clampedOffset, through: 0, by: -1),
                pageStarts: pageStarts
            ) {
                return previous
            }
            return visibleTextCharacterWithLocation(
                in: stride(from: clampedOffset + 1, to: totalLength, by: 1),
                pageStarts: pageStarts
            )
        }

        if let next = visibleTextCharacterWithLocation(
            in: stride(from: clampedOffset, to: totalLength, by: 1),
            pageStarts: pageStarts
        ) {
            return next
        }
        return visibleTextCharacterWithLocation(
            in: stride(from: clampedOffset - 1, through: 0, by: -1),
            pageStarts: pageStarts
        )
    }

    private func visibleTextCharacterWithLocation<S: Sequence>(
        in offsets: S,
        pageStarts: [Int]
    ) -> (pageIndex: Int, globalOffset: Int, bounds: NSRect)? where S.Element == Int {
        for offset in offsets {
            guard let pageIndex = pageIndex(containing: offset, pageStarts: pageStarts),
                  let page = document?.page(at: pageIndex) else { continue }

            let characterIndex = offset - pageStarts[pageIndex]
            guard characterIndex >= 0, characterIndex < page.numberOfCharacters else { continue }
            guard !isNewlineCharacter(at: characterIndex, in: page.string as NSString?) else { continue }

            let bounds = page.characterBounds(at: characterIndex)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            return (pageIndex, offset, bounds)
        }

        return nil
    }

    private func scrollTextCaretToVisible(_ caret: VimTextCaret) {
        guard let document,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView,
              let page = document.page(at: caret.pageIndex) else { return }

        guard let endpointRectInView = viewRect(
            for: NSRect(x: caret.point.x - 2, y: caret.point.y - 8, width: 4, height: 16),
            on: page
        ) else { return }

        scrollRectToComfortableTextArea(endpointRectInView, scrollView: scrollView, documentView: documentView)
    }

    private func scrollTextSelectionEndpointToVisible(
        anchorOffset: Int,
        extentOffset: Int,
        pageStarts: [Int]
    ) {
        guard let document,
              let totalLength = pageStarts.last,
              totalLength > 0,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView else { return }

        let activeOffset = activeCharacterOffset(
            extentOffset: extentOffset,
            anchorOffset: anchorOffset,
            totalLength: totalLength
        )
        guard let pageIndex = pageIndex(containing: activeOffset, pageStarts: pageStarts),
              let page = document.page(at: pageIndex) else { return }

        let localOffset = activeOffset - pageStarts[pageIndex]
        guard localOffset >= 0, localOffset < page.numberOfCharacters else { return }

        let characterBounds = page.characterBounds(at: localOffset).insetBy(dx: -8, dy: -10)
        guard characterBounds.width > 0, characterBounds.height > 0,
              let endpointRectInView = viewRect(for: characterBounds, on: page) else { return }

        scrollRectToComfortableTextArea(endpointRectInView, scrollView: scrollView, documentView: documentView)
    }

    private func scrollRectToComfortableTextArea(
        _ endpointRectInView: NSRect,
        scrollView: NSScrollView,
        documentView: NSView
    ) {
        let endpointRect = convert(endpointRectInView, to: documentView)
        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds
        let marginX = min(44, visibleRect.width * 0.12)
        let marginY = min(56, visibleRect.height * 0.14)
        let comfortableRect = visibleRect.insetBy(dx: marginX, dy: marginY)

        guard !comfortableRect.contains(endpointRect) else { return }

        let documentBounds = documentView.bounds
        let maxOriginX = max(documentBounds.minX, documentBounds.maxX - visibleRect.width)
        let maxOriginY = max(documentBounds.minY, documentBounds.maxY - visibleRect.height)
        var nextOrigin = visibleRect.origin

        if endpointRect.minX < comfortableRect.minX {
            nextOrigin.x += endpointRect.minX - comfortableRect.minX
        } else if endpointRect.maxX > comfortableRect.maxX {
            nextOrigin.x += endpointRect.maxX - comfortableRect.maxX
        }

        if endpointRect.minY < comfortableRect.minY {
            nextOrigin.y += endpointRect.minY - comfortableRect.minY
        } else if endpointRect.maxY > comfortableRect.maxY {
            nextOrigin.y += endpointRect.maxY - comfortableRect.maxY
        }

        nextOrigin.x = min(max(documentBounds.minX, nextOrigin.x), maxOriginX)
        nextOrigin.y = min(max(documentBounds.minY, nextOrigin.y), maxOriginY)

        guard abs(nextOrigin.x - visibleRect.origin.x) > 0.5
            || abs(nextOrigin.y - visibleRect.origin.y) > 0.5 else { return }

        clipView.scroll(to: nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func textPageStarts(in document: PDFDocument) -> [Int] {
        var starts: [Int] = []
        var offset = 0

        for pageIndex in 0..<document.pageCount {
            starts.append(offset)
            offset += document.page(at: pageIndex)?.numberOfCharacters ?? 0
        }

        starts.append(offset)
        return starts
    }

    private func wordForwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length)

        if index < length, characterClass(at: index, in: text) != .whitespace {
            let currentClass = characterClass(at: index, in: text)
            while index < length, characterClass(at: index, in: text) == currentClass {
                index += 1
            }
        }

        while index < length, characterClass(at: index, in: text) == .whitespace {
            index += 1
        }

        return index
    }

    private func wordBackwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length) - 1

        while index > 0, characterClass(at: index, in: text) == .whitespace {
            index -= 1
        }

        guard index >= 0 else { return 0 }
        let targetClass = characterClass(at: index, in: text)
        while index > 0, characterClass(at: index - 1, in: text) == targetClass {
            index -= 1
        }

        return index
    }

    private func wordEndOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length)

        while index < length, characterClass(at: index, in: text) == .whitespace {
            index += 1
        }

        guard index < length else { return length }
        let targetClass = characterClass(at: index, in: text)
        while index + 1 < length, characterClass(at: index + 1, in: text) == targetClass {
            index += 1
        }

        return min(length, index + 1)
    }

    private func documentText(in document: PDFDocument) -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()
    }

    private func characterClass(at offset: Int, in text: NSString) -> VimTextCharacterClass {
        guard offset >= 0, offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return .punctuation
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return .whitespace
        }

        if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
            return .word
        }

        return .punctuation
    }

    private func isNewlineCharacter(at offset: Int, in text: NSString?) -> Bool {
        guard let text,
              offset >= 0,
              offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return false
        }

        return CharacterSet.newlines.contains(scalar)
    }

    private func verticalSelectionCaret(
        from extentCaret: VimTextCaret?,
        fallbackExtentOffset: Int,
        anchorOffset: Int,
        anchorCaret: VimTextCaret?,
        direction: Int,
        preferredX: CGFloat?,
        pageStarts: [Int]
    ) -> (caret: VimTextCaret, preferredX: CGFloat)? {
        guard let document,
              let totalLength = pageStarts.last,
              totalLength > 0 else { return nil }

        let fallbackActiveOffset = activeCharacterOffset(
            extentOffset: fallbackExtentOffset,
            anchorOffset: anchorOffset,
            totalLength: totalLength
        )
        let activeCaret = extentCaret ?? textCaret(
            atInsertionOffset: fallbackExtentOffset,
            preferTrailingEdge: fallbackExtentOffset >= anchorOffset,
            pageStarts: pageStarts
        )
        let pageIndex = activeCaret?.pageIndex
            ?? pageIndex(containing: fallbackActiveOffset, pageStarts: pageStarts)
        guard let pageIndex else { return nil }

        let lines = textLines(onPageAt: pageIndex, pageStarts: pageStarts)
        guard let currentLineIndex = lineIndex(for: activeCaret, fallbackOffset: fallbackActiveOffset, in: lines) else { return nil }

        let currentX = preferredX ?? activeCaret?.point.x ?? caretX(
            near: fallbackActiveOffset,
            in: lines[currentLineIndex],
            selectionIsForward: fallbackExtentOffset >= anchorOffset,
            pageStarts: pageStarts
        )
        let currentLine = lines[currentLineIndex]
        guard let targetLine = targetLine(
            from: currentLine,
            direction: direction,
            document: document,
            pageStarts: pageStarts,
            preferredX: currentX
        ) else { return nil }

        guard var targetCaret = targetCaret(in: targetLine, preferredX: currentX) else { return nil }
        targetCaret = adjustedTargetCaret(
            targetCaret,
            targetLine: targetLine,
            anchorCaret: anchorCaret,
            pageStarts: pageStarts
        )
        return (targetCaret, currentX)
    }

    private func lineIndex(for caret: VimTextCaret?, fallbackOffset: Int, in lines: [VimTextLine]) -> Int? {
        guard !lines.isEmpty else { return nil }

        if let caret,
           let exactPageLine = lines.indices.min(by: { lhs, rhs in
               let lhsLine = lines[lhs]
               let rhsLine = lines[rhs]
               let lhsY = abs(lhsLine.midY - caret.lineMidY)
               let rhsY = abs(rhsLine.midY - caret.lineMidY)
               if abs(lhsY - rhsY) > 0.5 {
                   return lhsY < rhsY
               }
               return lineDistanceToX(caret.point.x, lhsLine) < lineDistanceToX(caret.point.x, rhsLine)
           }) {
            return exactPageLine
        }

        if let exactOffsetLine = lines.firstIndex(where: { line in
            line.characters.contains { $0.globalOffset == fallbackOffset }
        }) {
            return exactOffsetLine
        }

        return lines.indices.min { lhs, rhs in
            distance(from: fallbackOffset, to: lines[lhs]) < distance(from: fallbackOffset, to: lines[rhs])
        }
    }

    private func visualCaretPosition(
        for caret: VimTextCaret,
        pageStarts: [Int]
    ) -> VimTextCaretPosition? {
        let lines = textLines(onPageAt: caret.pageIndex, pageStarts: pageStarts)
        guard let lineIndex = lineIndex(for: caret, fallbackOffset: caret.offset, in: lines) else { return nil }
        let line = lines[lineIndex]
        let slotIndex = min(
            max(closestSlotIndex(to: caret.point.x, in: line, fallbackSlot: caret.slotIndex), 0),
            line.characters.count
        )

        return VimTextCaretPosition(
            pageIndex: caret.pageIndex,
            lineIndex: lineIndex,
            slotIndex: slotIndex
        )
    }

    private func compareVisualPosition(_ lhs: VimTextCaretPosition, _ rhs: VimTextCaretPosition) -> Int {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex ? -1 : 1
        }

        if lhs.lineIndex != rhs.lineIndex {
            return lhs.lineIndex < rhs.lineIndex ? -1 : 1
        }

        if lhs.slotIndex != rhs.slotIndex {
            return lhs.slotIndex < rhs.slotIndex ? -1 : 1
        }

        return 0
    }

    private func sameVisualCaret(_ lhs: VimTextCaret?, _ rhs: VimTextCaret?) -> Bool {
        guard let lhs, let rhs else { return false }

        return lhs.pageIndex == rhs.pageIndex
            && lhs.slotIndex == rhs.slotIndex
            && abs(lhs.lineMidY - rhs.lineMidY) < 0.5
    }

    private func averageCharacterHeight(in line: VimTextLine) -> CGFloat {
        guard !line.characters.isEmpty else { return 0 }
        return line.characters.reduce(CGFloat(0)) { $0 + $1.height } / CGFloat(line.characters.count)
    }

    private func distance(from offset: Int, to line: VimTextLine) -> Int {
        if offset < line.startOffset {
            return line.startOffset - offset
        }

        if offset >= line.endOffset {
            return offset - line.endOffset + 1
        }

        return 0
    }

    private func activeCharacterOffset(extentOffset: Int, anchorOffset: Int, totalLength: Int) -> Int {
        let offset = extentOffset >= anchorOffset ? extentOffset - 1 : extentOffset
        return min(max(offset, 0), max(0, totalLength - 1))
    }

    private func pageIndex(containing globalOffset: Int, pageStarts: [Int]) -> Int? {
        guard pageStarts.count > 1 else { return nil }

        for index in 0..<(pageStarts.count - 1) {
            if globalOffset >= pageStarts[index], globalOffset < pageStarts[index + 1] {
                return index
            }
        }

        return pageStarts.count >= 2 ? pageStarts.count - 2 : nil
    }

    private func textLines(onPageAt pageIndex: Int, pageStarts: [Int]) -> [VimTextLine] {
        guard let page = document?.page(at: pageIndex),
              pageIndex + 1 < pageStarts.count else { return [] }

        let pageStart = pageStarts[pageIndex]
        let pageText = page.string as NSString?
        var characters: [VimTextLineCharacter] = []
        for characterIndex in 0..<page.numberOfCharacters {
            guard !isNewlineCharacter(at: characterIndex, in: pageText) else { continue }

            let bounds = page.characterBounds(at: characterIndex)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            characters.append(
                VimTextLineCharacter(
                    globalOffset: pageStart + characterIndex,
                    minX: bounds.minX,
                    centerX: bounds.midX,
                    maxX: bounds.maxX,
                    centerY: bounds.midY,
                    height: bounds.height
                )
            )
        }

        let sortedCharacters = characters.sorted {
            if abs($0.centerY - $1.centerY) > 2 {
                return $0.centerY > $1.centerY
            }
            return $0.centerX < $1.centerX
        }

        var grouped: [[VimTextLineCharacter]] = []
        for character in sortedCharacters {
            if let last = grouped.indices.last,
               let reference = grouped[last].first {
                let threshold = max(2.0, max(reference.height, character.height) * 0.65)
                if abs(reference.centerY - character.centerY) <= threshold {
                    grouped[last].append(character)
                    continue
                }
            }
            grouped.append([character])
        }

        return grouped.flatMap { group in
            splitVisualLineSegments(group.sorted { $0.centerX < $1.centerX }).compactMap { lineCharacters in
                guard let start = lineCharacters.map(\.globalOffset).min(),
                      let end = lineCharacters.map(\.globalOffset).max().map({ $0 + 1 }) else {
                    return nil
                }

                let midY = lineCharacters.reduce(CGFloat(0)) { $0 + $1.centerY } / CGFloat(lineCharacters.count)
                return VimTextLine(
                    pageIndex: pageIndex,
                    startOffset: start,
                    endOffset: end,
                    midY: midY,
                    characters: lineCharacters
                )
            }
        }
    }

    private func splitVisualLineSegments(_ characters: [VimTextLineCharacter]) -> [[VimTextLineCharacter]] {
        guard !characters.isEmpty else { return [] }

        let averageWidth = characters.reduce(CGFloat(0)) { $0 + max(1, $1.maxX - $1.minX) } / CGFloat(characters.count)
        let gapThreshold = max(28, averageWidth * 5.5)
        var segments: [[VimTextLineCharacter]] = []
        var current: [VimTextLineCharacter] = []
        var previous: VimTextLineCharacter?

        for character in characters {
            if let previous,
               character.minX - previous.maxX > gapThreshold,
               !current.isEmpty {
                segments.append(current)
                current = []
            }

            current.append(character)
            previous = character
        }

        if !current.isEmpty {
            segments.append(current)
        }

        return segments
    }

    private func targetLine(
        from currentLine: VimTextLine,
        direction: Int,
        document: PDFDocument,
        pageStarts: [Int],
        preferredX: CGFloat
    ) -> VimTextLine? {
        let currentHeight = averageCharacterHeight(in: currentLine)
        let sameRowThreshold = max(2, currentHeight * 0.7)
        let currentPageLines = textLines(onPageAt: currentLine.pageIndex, pageStarts: pageStarts)

        let samePageCandidates = currentPageLines.filter { candidate in
            if direction > 0 {
                return currentLine.midY - candidate.midY > sameRowThreshold
            }

            return candidate.midY - currentLine.midY > sameRowThreshold
        }

        if let line = bestTargetLine(from: currentLine, candidates: samePageCandidates, preferredX: preferredX) {
            return line
        }

        if direction > 0 {
            for nextPageIndex in (currentLine.pageIndex + 1)..<document.pageCount {
                let lines = textLines(onPageAt: nextPageIndex, pageStarts: pageStarts)
                if let line = edgeLine(in: lines, edge: .top, preferredX: preferredX) {
                    return line
                }
            }
        } else if currentLine.pageIndex > 0 {
            for previousPageIndex in stride(from: currentLine.pageIndex - 1, through: 0, by: -1) {
                let lines = textLines(onPageAt: previousPageIndex, pageStarts: pageStarts)
                if let line = edgeLine(in: lines, edge: .bottom, preferredX: preferredX) {
                    return line
                }
            }
        }

        return nil
    }

    private enum VisualLineEdge {
        case top
        case bottom
    }

    private func bestTargetLine(
        from currentLine: VimTextLine,
        candidates: [VimTextLine],
        preferredX: CGFloat
    ) -> VimTextLine? {
        candidates.min { lhs, rhs in
            let lhsVerticalDistance = abs(lhs.midY - currentLine.midY)
            let rhsVerticalDistance = abs(rhs.midY - currentLine.midY)

            if abs(lhsVerticalDistance - rhsVerticalDistance) > max(1, averageCharacterHeight(in: currentLine) * 0.25) {
                return lhsVerticalDistance < rhsVerticalDistance
            }

            let lhsXDistance = lineDistanceToX(preferredX, lhs)
            let rhsXDistance = lineDistanceToX(preferredX, rhs)
            if abs(lhsXDistance - rhsXDistance) > 0.5 {
                return lhsXDistance < rhsXDistance
            }

            return lhs.characters.first?.minX ?? 0 < rhs.characters.first?.minX ?? 0
        }
    }

    private func edgeLine(in lines: [VimTextLine], edge: VisualLineEdge, preferredX: CGFloat) -> VimTextLine? {
        guard !lines.isEmpty else { return nil }

        let edgeY: CGFloat
        switch edge {
        case .top:
            edgeY = lines.map(\.midY).max() ?? 0
        case .bottom:
            edgeY = lines.map(\.midY).min() ?? 0
        }

        let rowTolerance = max(2, (lines.map { averageCharacterHeight(in: $0) }.max() ?? 0) * 0.7)
        let edgeLines = lines.filter { abs($0.midY - edgeY) <= rowTolerance }
        return edgeLines.min { lhs, rhs in
            lineDistanceToX(preferredX, lhs) < lineDistanceToX(preferredX, rhs)
        }
    }

    private func lineDistanceToX(_ x: CGFloat, _ line: VimTextLine) -> CGFloat {
        guard let first = line.characters.first,
              let last = line.characters.last else { return .greatestFiniteMagnitude }

        if x < first.minX {
            return first.minX - x
        }

        if x > last.maxX {
            return x - last.maxX
        }

        return 0
    }

    private func caretX(
        near globalOffset: Int,
        in line: VimTextLine,
        selectionIsForward: Bool,
        pageStarts: [Int]
    ) -> CGFloat {
        if let nearest = line.characters.min(by: {
            abs($0.globalOffset - globalOffset) < abs($1.globalOffset - globalOffset)
        }) {
            return selectionIsForward ? nearest.maxX : nearest.minX
        }

        return characterCenterX(globalOffset: globalOffset, pageStarts: pageStarts)
    }

    private func targetCaret(
        in line: VimTextLine,
        preferredX: CGFloat
    ) -> VimTextCaret? {
        guard document?.page(at: line.pageIndex) != nil else { return nil }

        let slots = (0...line.characters.count).map { slotIndex in
            let point = pointForSlot(slotIndex, in: line)
            return VimTextCaret(
                offset: offsetForSlot(slotIndex, in: line),
                pageIndex: line.pageIndex,
                slotIndex: slotIndex,
                point: point,
                lineMidY: line.midY
            )
        }

        guard !slots.isEmpty else { return nil }

        let clampedX = min(
            max(preferredX, line.characters.first?.minX ?? preferredX),
            line.characters.last?.maxX ?? preferredX
        )

        return slots.min { lhs, rhs in
            let lhsDistance = abs(lhs.point.x - clampedX)
            let rhsDistance = abs(rhs.point.x - clampedX)

            if abs(lhsDistance - rhsDistance) < 0.001 {
                return lhs.offset > rhs.offset
            }

            return lhsDistance < rhsDistance
        }
    }

    private func adjustedTargetCaret(
        _ caret: VimTextCaret,
        targetLine: VimTextLine,
        anchorCaret: VimTextCaret?,
        pageStarts: [Int]
    ) -> VimTextCaret {
        guard let anchorCaret,
              let anchorPosition = visualCaretPosition(for: anchorCaret, pageStarts: pageStarts),
              let targetPosition = visualCaretPosition(for: caret, pageStarts: pageStarts) else {
            return caret
        }

        let comparison = compareVisualPosition(anchorPosition, targetPosition)
        var slotIndex = caret.slotIndex

        if comparison < 0, slotIndex == 0, !targetLine.characters.isEmpty {
            slotIndex = 1
        } else if comparison > 0, slotIndex == targetLine.characters.count, !targetLine.characters.isEmpty {
            slotIndex = max(0, targetLine.characters.count - 1)
        }

        guard slotIndex != caret.slotIndex else { return caret }

        let point = pointForSlot(slotIndex, in: targetLine)
        return VimTextCaret(
            offset: offsetForSlot(slotIndex, in: targetLine),
            pageIndex: targetLine.pageIndex,
            slotIndex: slotIndex,
            point: point,
            lineMidY: targetLine.midY
        )
    }

    private func closestSlotIndex(to x: CGFloat, in line: VimTextLine, fallbackSlot: Int) -> Int {
        guard !line.characters.isEmpty else { return 0 }

        let slots = (0...line.characters.count).map { slotIndex in
            (slotIndex: slotIndex, point: pointForSlot(slotIndex, in: line))
        }

        return slots.min { lhs, rhs in
            let lhsDistance = abs(lhs.point.x - x)
            let rhsDistance = abs(rhs.point.x - x)

            if abs(lhsDistance - rhsDistance) < 0.001 {
                return abs(lhs.slotIndex - fallbackSlot) < abs(rhs.slotIndex - fallbackSlot)
            }

            return lhsDistance < rhsDistance
        }?.slotIndex ?? fallbackSlot
    }

    private func slotIndex(
        forInsertionOffset insertionOffset: Int,
        preferTrailingEdge: Bool,
        in line: VimTextLine
    ) -> Int {
        guard !line.characters.isEmpty else { return 0 }

        if preferTrailingEdge,
           let previousIndex = line.characters.lastIndex(where: { $0.globalOffset < insertionOffset }) {
            return min(line.characters.count, previousIndex + 1)
        }

        if let exactIndex = line.characters.firstIndex(where: { $0.globalOffset >= insertionOffset }) {
            return exactIndex
        }

        return line.characters.count
    }

    private func pointForSlot(_ slotIndex: Int, in line: VimTextLine) -> NSPoint {
        guard !line.characters.isEmpty else {
            return NSPoint(x: 0, y: line.midY)
        }

        if slotIndex <= 0, let first = line.characters.first {
            return NSPoint(x: first.minX, y: first.centerY)
        }

        if slotIndex >= line.characters.count, let last = line.characters.last {
            return NSPoint(x: last.maxX, y: last.centerY)
        }

        let previous = line.characters[slotIndex - 1]
        let next = line.characters[slotIndex]
        return NSPoint(
            x: max(previous.maxX, next.minX),
            y: (previous.centerY + next.centerY) / 2
        )
    }

    private func offsetForSlot(_ slotIndex: Int, in line: VimTextLine) -> Int {
        guard !line.characters.isEmpty else { return line.startOffset }

        if slotIndex <= 0 {
            return line.characters[0].globalOffset
        }

        if slotIndex >= line.characters.count {
            return line.characters[line.characters.count - 1].globalOffset + 1
        }

        return line.characters[slotIndex].globalOffset
    }

    private func characterCenterX(globalOffset: Int, pageStarts: [Int]) -> CGFloat {
        guard let pageIndex = pageIndex(containing: globalOffset, pageStarts: pageStarts),
              let page = document?.page(at: pageIndex) else { return 0 }

        let localOffset = globalOffset - pageStarts[pageIndex]
        return page.characterBounds(at: localOffset).midX
    }

    func vimScroll(x: CGFloat, y: CGFloat) {
        guard let scrollView = pdfScrollView else { return }
        cancelPendingRestore()
        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let origin = scrollTargetOrigin ?? clipView.bounds.origin
        let next = NSPoint(
            x: nextScrollCoordinate(
                origin: origin.x,
                delta: x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: nextScrollCoordinate(
                origin: origin.y,
                delta: y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )
        scrollTargetOrigin = next
        ensureScrollAnimation(in: scrollView)
    }

    func vimMoveByPage(_ delta: Int) {
        guard let document,
              let pageState = currentPageState(),
              let targetPage = document.page(at: pageState.pageIndex + delta) else { return }

        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()

        let targetBounds = targetPage.bounds(for: displayBox)
        let yRatio = pageState.pageBounds.height == 0
            ? 0
            : (pageState.pointOnPage.y - pageState.pageBounds.minY) / pageState.pageBounds.height
        let targetY = targetBounds.minY + targetBounds.height * min(max(yRatio, 0), 1)
        let targetPoint = NSPoint(x: targetBounds.midX, y: targetY)

        go(to: PDFDestination(page: targetPage, at: targetPoint))
        DispatchQueue.main.async { [weak self] in
            self?.centerVertically(on: PDFDestination(page: targetPage, at: targetPoint))
        }
    }

    func vimHighlightSelection(color: NSColor) {
        guard let selection = currentSelection else {
            NSSound.beep()
            return
        }

        let annotations = addHighlightAnnotations(for: selection, color: color)
        guard !annotations.isEmpty else {
            NSSound.beep()
            return
        }

        clearSelection()
        textSelectionNavigationState = nil
        needsDisplay = true
        persistAnnotationsIfPossible()
    }

    @discardableResult
    private func addHighlightAnnotations(for selection: PDFSelection, color: NSColor) -> [PDFAnnotation] {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var annotations: [PDFAnnotation] = []
        let groupID = UUID().uuidString

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = tightHighlightBounds(for: lineSelection, on: page) else { continue }

                let preservedExplanation = existingAIExplanation(on: page, intersecting: [bounds])
                removeHighlightAnnotations(on: page, intersecting: bounds)

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                annotation.quadrilateralPoints = quadrilateralPoints(for: bounds)
                HighlightAnnotationMetadata.setGroupID(groupID, for: annotation)
                if let preservedExplanation {
                    annotation.contents = AIExplanationAnnotation.encode(preservedExplanation)
                    annotation.userName = "VimPDF AI"
                }
                annotation.shouldDisplay = true
                annotation.shouldPrint = true
                page.addAnnotation(annotation)
                annotations.append(annotation)
            }
        }

        return annotations
    }

    func vimDeleteHighlightsForSelection() -> Bool {
        guard let selection = currentSelection else { return false }

        let selectionsByPage = highlightSelectionBoundsByPage(for: selection)
        var didRemoveHighlight = false

        for pageSelection in selectionsByPage {
            didRemoveHighlight = removeHighlightAnnotations(
                on: pageSelection.page,
                intersecting: pageSelection.bounds
            ) || didRemoveHighlight
        }

        guard didRemoveHighlight else {
            NSSound.beep()
            return true
        }

        clearSelection()
        needsDisplay = true
        persistAnnotationsIfPossible()
        return true
    }

    func vimExplainSelectedHighlight() {
        guard let selection = currentSelection,
              let selectedText = selection.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        let anchor = selectionPopoverRect(for: selection)
        let targetAnnotations = highlightedAnnotations(intersecting: selection)

        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current()
        } catch {
            showAIMessage(error.localizedDescription)
            NSSound.beep()
            return
        }

        guard let context = aiExplanationContext(for: selection, selectedText: selectedText) else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        activeAIExplanationTask?.cancel()
        activeAISelection = selection.copy() as? PDFSelection ?? selection
        activeAIExistingAnnotations = targetAnnotations
        let popoverModel = showStreamingAIExplanationPopover(
            title: selectedText.aiPopoverTitle,
            at: anchor
        )

        let task = Task { @MainActor [weak self] in
            do {
                let explanation = try await AIExplanationClient.streamExplanation(
                    context: context,
                    configuration: configuration,
                    onChunk: { chunk in
                        popoverModel?.append(chunk)
                    }
                )
                guard let self else { return }

                for annotation in self.activeAIExistingAnnotations {
                    annotation.contents = AIExplanationAnnotation.encode(explanation)
                    annotation.userName = "VimPDF AI"
                    annotation.modificationDate = Date()
                }

                if !self.activeAIExistingAnnotations.isEmpty {
                    self.needsDisplay = true
                    self.persistAnnotationsIfPossible()
                }
                popoverModel?.isStreaming = false
                self.activeAIExplanationTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.activeAIExplanationTask = nil
                popoverModel?.isStreaming = false
                popoverModel?.title = "AI request failed"
                popoverModel?.text = error.localizedDescription
                NSSound.beep()
            }
        }
        activeAIExplanationTask = task
    }

    func vimZoom(by factor: CGFloat) {
        cancelPendingRestore()
        let baseScale = zoomTargetScale ?? scaleFactor
        vimZoom(to: baseScale * factor)
    }

    func vimZoom(to targetScale: CGFloat) {
        cancelPendingRestore()
        stopScrollAnimation()
        autoScales = false
        prepareZoomAnchor()
        zoomTargetScale = min(max(targetScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToFit() {
        cancelPendingRestore()
        stopScrollAnimation()
        guard let fitScale = widthFitScale() else { return }
        zoomAnchor = centerDestination() ?? currentDestination
        zoomTargetScale = min(max(fitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToPageFit() {
        cancelPendingRestore()
        stopScrollAnimation()
        guard let pageState = currentPageState(),
              let pageFitScale = pageFitScale(for: pageState.page) else { return }

        zoomAnchor = pageCenterDestination(for: pageState.page)
        zoomTargetScale = min(max(pageFitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimGoToFirstPage() {
        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        goToFirstPage(nil)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToDocumentEdge(.top)
        }
    }

    func vimGoToLastPage() {
        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        goToLastPage(nil)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToDocumentEdge(.bottom)
        }
    }

    func vimGoToPage(_ pageNumber: Int) {
        guard let document, document.pageCount > 0 else { return }

        let pageIndex = min(max(pageNumber - 1, 0), document.pageCount - 1)
        guard let page = document.page(at: pageIndex) else { return }

        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()

        let destination = topDestination(for: page)
        go(to: destination)
        DispatchQueue.main.async { [weak self] in
            self?.go(to: destination)
        }
    }

    func vimGoToDestination(_ destination: PDFDestination) {
        let horizontalOrigin = currentHorizontalOrigin()

        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()

        go(to: destination)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.go(to: destination)
            self.restoreHorizontalOrigin(horizontalOrigin)

            DispatchQueue.main.async { [weak self] in
                self?.restoreHorizontalOrigin(horizontalOrigin)
            }
        }
    }

    func vimJumpBack() {
        guard let targetSnapshot = jumpBackStack.popLast() else { return }

        cancelPendingRestore()
        if let current = self.snapshot() {
            jumpForwardStack.append(current)
            trimJumpStacks()
        }

        restore(targetSnapshot)
    }

    func vimJumpForward() {
        guard let targetSnapshot = jumpForwardStack.popLast() else { return }

        cancelPendingRestore()
        if let current = self.snapshot() {
            jumpBackStack.append(current)
            trimJumpStacks()
        }

        restore(targetSnapshot)
    }

    func snapshot() -> ReaderSnapshot? {
        guard let document else { return nil }

        if let scrollView = pdfScrollView {
            let clipView = scrollView.contentView
            let visibleCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
            let pointInPDFView = convert(visibleCenter, from: clipView)

            if let page = page(for: pointInPDFView, nearest: true) {
                return ReaderSnapshot(
                    pageIndex: document.index(for: page),
                    pointOnPage: convert(pointInPDFView, to: page),
                    scrollOrigin: clipView.bounds.origin,
                    scaleFactor: scaleFactor,
                    autoScales: autoScales
                )
            }
        }

        guard let destination = currentDestination,
              let page = destination.page else { return nil }

        return ReaderSnapshot(
            pageIndex: document.index(for: page),
            pointOnPage: destination.point,
            scrollOrigin: nil,
            scaleFactor: scaleFactor,
            autoScales: autoScales
        )
    }

    func restore(_ snapshot: ReaderSnapshot?) {
        restoreGeneration += 1
        let generation = restoreGeneration
        stopScrollAnimation()
        stopZoomState()

        if snapshot == .initial {
            restoreInitialDocumentPosition(generation: generation)
            return
        }

        guard let snapshot, let document, let page = document.page(at: snapshot.pageIndex) else {
            _ = applyWidthFitScaleNow()
            return
        }

        autoScales = false
        if snapshot.autoScales {
            _ = applyWidthFitScaleNow()
        } else {
            scaleFactor = snapshot.scaleFactor
            layoutDocumentView()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.go(to: PDFDestination(page: page, at: snapshot.pointOnPage))
            self.restoreScrollOrigin(snapshot.scrollOrigin)

            DispatchQueue.main.async { [weak self] in
                self?.restoreScrollOrigin(snapshot.scrollOrigin)
            }
        }
    }

    private func restoreInitialDocumentPosition(
        generation: Int,
        attemptsRemaining: Int = 30,
        stablePasses: Int = 0,
        lastViewportSize: NSSize? = nil
    ) {
        guard generation == restoreGeneration else { return }

        let viewportSize = fitViewportSize()
        let didFit = applyWidthFitScaleNow(for: document?.page(at: 0))
        if didFit {
            goToFirstPage(nil)
            scrollToDocumentEdge(.top)
        }

        let nextStablePasses: Int
        if didFit,
           let viewportSize,
           let lastViewportSize,
           isSameViewportSize(viewportSize, lastViewportSize) {
            nextStablePasses = stablePasses + 1
        } else {
            nextStablePasses = 0
        }

        guard attemptsRemaining > 0, (!didFit || nextStablePasses < 2) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.restoreInitialDocumentPosition(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1,
                stablePasses: nextStablePasses,
                lastViewportSize: viewportSize
            )
        }
    }

    private func recordJumpSource() {
        guard let current = snapshot() else { return }

        if let last = jumpBackStack.last, isSameJumpLocation(last, current) {
            jumpForwardStack.removeAll()
            return
        }

        jumpBackStack.append(current)
        jumpForwardStack.removeAll()
        trimJumpStacks()
    }

    private func trimJumpStacks() {
        if jumpBackStack.count > 100 {
            jumpBackStack.removeFirst(jumpBackStack.count - 100)
        }

        if jumpForwardStack.count > 100 {
            jumpForwardStack.removeFirst(jumpForwardStack.count - 100)
        }
    }

    private func isSameJumpLocation(_ lhs: ReaderSnapshot, _ rhs: ReaderSnapshot) -> Bool {
        lhs.pageIndex == rhs.pageIndex
            && abs(lhs.pointOnPage.x - rhs.pointOnPage.x) < 2
            && abs(lhs.pointOnPage.y - rhs.pointOnPage.y) < 2
    }

    private func restoreScrollOrigin(_ origin: NSPoint?) {
        guard let origin, let scrollView = pdfScrollView else { return }
        stopScrollAnimation()

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let clamped = NSPoint(
            x: restoredScrollCoordinate(
                origin: origin.x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: restoredScrollCoordinate(
                origin: origin.y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        clipView.scroll(to: clamped)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func persistAnnotationsIfPossible() {
        guard let document, let url = document.documentURL else { return }
        if !document.write(to: url) {
            NSSound.beep()
        }
    }

    @discardableResult
    private func removeHighlightAnnotations(on page: PDFPage, intersecting bounds: NSRect) -> Bool {
        removeHighlightAnnotations(on: page, intersecting: [bounds])
    }

    @discardableResult
    private func removeHighlightAnnotations(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> Bool {
        let highlights = highlightAnnotationsToRemove(on: page, intersecting: selectionBounds)

        for annotation in highlights {
            page.removeAnnotation(annotation)
        }

        return !highlights.isEmpty
    }

    private func highlightAnnotationsToRemove(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> [PDFAnnotation] {
        let directlyHitHighlights = highlightAnnotations(on: page, intersecting: selectionBounds)
        var seen = Set<ObjectIdentifier>()
        var result: [PDFAnnotation] = []

        for annotation in directlyHitHighlights {
            for groupedAnnotation in highlightGroupAnnotations(for: annotation, on: page) {
                let identifier = ObjectIdentifier(groupedAnnotation)
                guard seen.insert(identifier).inserted else { continue }
                result.append(groupedAnnotation)
            }
        }

        return result
    }

    private func highlightGroupAnnotations(for seed: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        if let groupID = HighlightAnnotationMetadata.groupID(for: seed) {
            return page.annotations.filter { annotation in
                annotation.type == "Highlight"
                    && HighlightAnnotationMetadata.groupID(for: annotation) == groupID
            }
        }

        if let explanation = AIExplanationAnnotation.decode(seed.contents) {
            return explanationAnnotations(matching: explanation, on: page)
        }

        return legacyConnectedHighlightGroup(for: seed, on: page)
    }

    private func legacyConnectedHighlightGroup(for seed: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        let candidates = page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && HighlightAnnotationMetadata.groupID(for: annotation) == nil
                && AIExplanationAnnotation.decode(annotation.contents) == nil
                && highlightColor(annotation.color, matches: seed.color)
        }
        var result: [PDFAnnotation] = []
        var queue: [PDFAnnotation] = [seed]
        var seen = Set<ObjectIdentifier>()

        while let annotation = queue.popLast() {
            let identifier = ObjectIdentifier(annotation)
            guard seen.insert(identifier).inserted else { continue }
            result.append(annotation)

            for candidate in candidates where !seen.contains(ObjectIdentifier(candidate)) {
                if highlight(annotation, isConnectedTo: candidate) {
                    queue.append(candidate)
                }
            }
        }

        return result
    }

    private func existingAIExplanation(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> String? {
        highlightAnnotations(on: page, intersecting: selectionBounds)
            .compactMap { AIExplanationAnnotation.decode($0.contents) }
            .first
    }

    private func highlightedAnnotations(intersecting selection: PDFSelection) -> [PDFAnnotation] {
        let selectionsByPage = highlightSelectionBoundsByPage(for: selection)
        var seen = Set<ObjectIdentifier>()
        var annotations: [PDFAnnotation] = []

        for pageSelection in selectionsByPage {
            for annotation in highlightAnnotations(on: pageSelection.page, intersecting: pageSelection.bounds) {
                let identifier = ObjectIdentifier(annotation)
                guard seen.insert(identifier).inserted else { continue }
                annotations.append(annotation)
            }
        }

        return annotations
    }

    private func highlightAnnotations(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> [PDFAnnotation] {
        guard !selectionBounds.isEmpty else { return [] }

        return page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && highlightRegions(for: annotation).contains { highlightBounds in
                    selectionBounds.contains { selectedBounds in
                        highlight(highlightBounds, matches: selectedBounds)
                    }
                }
        }
    }

    private struct PageSelectionBounds {
        var page: PDFPage
        var bounds: [NSRect]
    }

    private func highlightSelectionBoundsByPage(for selection: PDFSelection) -> [PageSelectionBounds] {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var result: [PageSelectionBounds] = []

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = tightHighlightBounds(for: lineSelection, on: page) else { continue }

                if let index = result.firstIndex(where: { $0.page === page }) {
                    result[index].bounds.append(bounds)
                } else {
                    result.append(PageSelectionBounds(page: page, bounds: [bounds]))
                }
            }
        }

        return result
    }

    private func aiExplanationContext(
        for selection: PDFSelection,
        selectedText: String
    ) -> AIExplanationContext? {
        guard let document else { return nil }

        let pages = selection.pages
        let pageNumbers = pages.compactMap { page -> Int? in
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index + 1
        }
        let pageText = pages
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: "\n\n")
        let paragraphContext = paragraphContext(
            selectedText: selectedText,
            in: pageText
        )
        let url = document.documentURL

        return AIExplanationContext(
            selectedText: selectedText,
            previousParagraph: paragraphContext.previous,
            currentParagraph: paragraphContext.current,
            nextParagraph: paragraphContext.next,
            nearbyText: paragraphContext.nearby,
            fileName: url?.lastPathComponent ?? "Untitled PDF",
            directoryName: url?.deletingLastPathComponent().lastPathComponent,
            outlineTitle: document.outlineItem(for: selection)?.label?.nilIfEmpty,
            pageNumbers: pageNumbers.isEmpty ? [1] : pageNumbers
        )
    }

    private func paragraphContext(
        selectedText: String,
        in text: String
    ) -> (previous: String?, current: String?, next: String?, nearby: String) {
        let paragraphs = paragraphs(from: text)
        let selectedNeedle = selectedText.normalizedForAIContext.prefixString(240)

        if let index = paragraphs.firstIndex(where: { paragraph in
            let normalized = paragraph.normalizedForAIContext
            return normalized.contains(selectedNeedle)
                || selectedNeedle.contains(normalized.prefixString(240))
        }) {
            let previous = index > 0 ? paragraphs[index - 1] : nil
            let current = paragraphs[index]
            let next = index + 1 < paragraphs.count ? paragraphs[index + 1] : nil
            let nearby = [previous, current, next]
                .compactMap { $0 }
                .joined(separator: "\n\n")
                .limitedForAIContext()
            return (previous, current, next, nearby)
        }

        return (
            nil,
            nil,
            nil,
            text.trimmingCharacters(in: .whitespacesAndNewlines).limitedForAIContext()
        )
    }

    private func paragraphs(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [String] = []
        var currentLines: [String] = []

        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !currentLines.isEmpty {
                    paragraphs.append(currentLines.joined(separator: " "))
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(trimmed)
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(currentLines.joined(separator: " "))
        }

        if paragraphs.count > 1 {
            return paragraphs.map { $0.limitedForAIContext(1600) }
        }

        return normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .chunked(maxCharacters: 900)
            .map { $0.limitedForAIContext(1600) }
    }

    private func tightHighlightBounds(for selection: PDFSelection, on page: PDFPage) -> NSRect? {
        let rawBounds = selection.bounds(for: page)
        guard rawBounds.width > 0, rawBounds.height > 0 else { return nil }

        let verticalInset = min(max(rawBounds.height * 0.10, 0.45), 1.4)
        let horizontalOutset: CGFloat = 0.35
        let bounds = rawBounds.insetBy(dx: -horizontalOutset, dy: verticalInset)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        return bounds
    }

    private func quadrilateralPoints(for bounds: NSRect) -> [NSValue] {
        [
            NSValue(point: NSPoint(x: 0, y: bounds.height)),
            NSValue(point: NSPoint(x: bounds.width, y: bounds.height)),
            NSValue(point: NSPoint(x: 0, y: 0)),
            NSValue(point: NSPoint(x: bounds.width, y: 0))
        ]
    }

    private func highlightRegions(for annotation: PDFAnnotation) -> [NSRect] {
        guard let quadrilateralPoints = annotation.quadrilateralPoints,
              quadrilateralPoints.count >= 4 else {
            return [annotation.bounds]
        }

        let regions = stride(from: 0, to: quadrilateralPoints.count - 3, by: 4).compactMap { index in
            quadBounds(
                Array(quadrilateralPoints[index..<(index + 4)]),
                relativeTo: annotation.bounds
            )
        }

        return regions.isEmpty ? [annotation.bounds] : regions
    }

    private func quadBounds(_ values: [NSValue], relativeTo annotationBounds: NSRect) -> NSRect? {
        let points = values.map(\.pointValue)
        guard points.count == 4 else { return nil }

        guard let relativeBounds = rect(containing: points.map { point in
            NSPoint(x: annotationBounds.minX + point.x, y: annotationBounds.minY + point.y)
        }),
              let absoluteBounds = rect(containing: points) else {
            return nil
        }
        let expandedAnnotationBounds = annotationBounds.insetBy(dx: -1, dy: -1)

        if expandedAnnotationBounds.intersects(relativeBounds) {
            return relativeBounds
        }

        if expandedAnnotationBounds.intersects(absoluteBounds) {
            return absoluteBounds
        }

        return relativeBounds
    }

    private func rect(containing points: [NSPoint]) -> NSRect? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max(),
              maxX > minX,
              maxY > minY else {
            return nil
        }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func highlight(_ annotationBounds: NSRect, matches selectionBounds: NSRect) -> Bool {
        guard annotationBounds.width > 0,
              annotationBounds.height > 0,
              selectionBounds.width > 0,
              selectionBounds.height > 0 else {
            return false
        }

        let intersection = annotationBounds.intersection(selectionBounds)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return false
        }

        let verticalOverlap = intersection.height / min(annotationBounds.height, selectionBounds.height)
        guard verticalOverlap >= 0.55 else { return false }

        if selectionBounds.contains(center(of: annotationBounds))
            || annotationBounds.contains(center(of: selectionBounds)) {
            return true
        }

        let annotationArea = annotationBounds.width * annotationBounds.height
        let selectionArea = selectionBounds.width * selectionBounds.height
        let intersectionArea = intersection.width * intersection.height
        let smallerArea = min(annotationArea, selectionArea)

        return smallerArea > 0 && intersectionArea / smallerArea >= 0.42
    }

    private func highlight(_ lhs: PDFAnnotation, isConnectedTo rhs: PDFAnnotation) -> Bool {
        if lhs === rhs { return true }

        return highlightRegions(for: lhs).contains { lhsRegion in
            highlightRegions(for: rhs).contains { rhsRegion in
                highlight(lhsRegion, isConnectedTo: rhsRegion)
            }
        }
    }

    private func highlight(_ lhs: NSRect, isConnectedTo rhs: NSRect) -> Bool {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else {
            return false
        }

        if lhs.intersects(rhs) {
            return true
        }

        let verticalGap = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
        let horizontalGap = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
        let lineHeight = min(lhs.height, rhs.height)
        let adjacentLineGap = max(2.5, lineHeight * 0.9)
        let relatedHorizontalGap = max(24, lineHeight * 6)

        return verticalGap <= adjacentLineGap && horizontalGap <= relatedHorizontalGap
    }

    private func highlightColor(_ lhs: NSColor?, matches rhs: NSColor?) -> Bool {
        guard let lhs = lhs?.usingColorSpace(.deviceRGB),
              let rhs = rhs?.usingColorSpace(.deviceRGB) else {
            return lhs == nil && rhs == nil
        }

        return abs(lhs.redComponent - rhs.redComponent) < 0.015
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.015
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.015
            && abs(lhs.alphaComponent - rhs.alphaComponent) < 0.03
    }

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    private func currentHorizontalOrigin() -> CGFloat? {
        pdfScrollView?.contentView.bounds.origin.x
    }

    private func restoreHorizontalOrigin(_ originX: CGFloat?) {
        guard let originX, let scrollView = pdfScrollView else { return }

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let clampedX = restoredScrollCoordinate(
            origin: originX,
            contentLength: documentSize.width,
            viewportLength: clipView.bounds.width,
            maxValue: maxX
        )

        clipView.scroll(to: NSPoint(x: clampedX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func ensureScrollAnimation(in scrollView: NSScrollView) {
        guard scrollTimer?.isValid != true else { return }

        lastScrollTick = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak scrollView] timer in
            guard let self, let scrollView else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                self.stepScrollAnimation(in: scrollView)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func stepScrollAnimation(in scrollView: NSScrollView) {
        guard let target = scrollTargetOrigin else {
            stopScrollAnimation()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = min(max(now - lastScrollTick, 1.0 / 240.0), 1.0 / 30.0)
        lastScrollTick = now

        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let deltaX = target.x - origin.x
        let deltaY = target.y - origin.y

        if abs(deltaX) < 0.45, abs(deltaY) < 0.45 {
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
            stopScrollAnimation()
            return
        }

        let progress = 1 - CGFloat(exp(-deltaTime / 0.055))
        let next = NSPoint(
            x: origin.x + deltaX * progress,
            y: origin.y + deltaY * progress
        )
        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func stopScrollAnimation() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollTargetOrigin = nil
    }

    private func prepareZoomAnchor() {
        if zoomAnchor == nil {
            zoomAnchor = centerDestination() ?? currentDestination
        }
    }

    private func ensureZoomAnimation() {
        guard zoomTimer?.isValid != true else { return }

        lastZoomTick = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                self.stepZoomAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        zoomTimer = timer
    }

    private func stepZoomAnimation() {
        guard let target = zoomTargetScale else {
            stopZoomState()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = min(max(now - lastZoomTick, 1.0 / 120.0), 1.0 / 30.0)
        lastZoomTick = now

        let current = scaleFactor
        let delta = target - current
        let threshold = max(0.001, target * 0.0008)

        if abs(delta) < threshold {
            applyZoomScale(target)
            stopZoomState()
            return
        }

        let progress = 1 - CGFloat(exp(-deltaTime / 0.11))
        applyZoomScale(current + delta * progress)
    }

    private func applyZoomScale(_ scale: CGFloat) {
        autoScales = false
        scaleFactor = min(max(scale, minimumZoomScale), maximumZoomScale)
        layoutDocumentView()

        if let zoomAnchor {
            centerBothAxes(on: zoomAnchor)
        }
    }

    private func stopZoomState() {
        zoomTimer?.invalidate()
        zoomTimer = nil
        zoomTargetScale = nil
        zoomAnchor = nil
    }

    private func cancelPendingRestore() {
        restoreGeneration += 1
    }

    @discardableResult
    private func applyWidthFitScaleNow(for page: PDFPage? = nil) -> Bool {
        guard let fitScale = widthFitScale(for: page) else { return false }

        autoScales = false
        scaleFactor = fitScale
        layoutDocumentView()
        needsDisplay = true
        return true
    }

    private func widthFitScale(for explicitPage: PDFPage? = nil) -> CGFloat? {
        guard let page = explicitPage ?? currentPage ?? currentDestination?.page ?? document?.page(at: 0),
              let viewportSize = fitViewportSize(),
              let pageSize = displaySize(for: page) else { return nil }

        return clampedScale((viewportSize.width * 0.985) / pageSize.width)
    }

    private func pageFitScale(for page: PDFPage) -> CGFloat? {
        guard let viewportSize = fitViewportSize(),
              let pageSize = displaySize(for: page) else { return nil }

        let widthScale = (viewportSize.width * 0.985) / pageSize.width
        let heightScale = (viewportSize.height * 0.985) / pageSize.height
        return clampedScale(min(widthScale, heightScale))
    }

    private func fitViewportSize() -> NSSize? {
        guard window != nil, let scrollView = pdfScrollView else { return nil }

        layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()

        let viewportSize = scrollView.contentView.frame.size
        guard viewportSize.width > 100, viewportSize.height > 100 else { return nil }

        return viewportSize
    }

    private func displaySize(for page: PDFPage) -> NSSize? {
        let bounds = page.bounds(for: displayBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let normalizedRotation = ((page.rotation % 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return NSSize(width: bounds.height, height: bounds.width)
        }

        return bounds.size
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumZoomScale), maximumZoomScale)
    }

    private func isSameViewportSize(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    private func pageCenterDestination(for page: PDFPage) -> PDFDestination {
        let bounds = page.bounds(for: displayBox)
        return PDFDestination(page: page, at: NSPoint(x: bounds.midX, y: bounds.midY))
    }

    private func centerDestination() -> PDFDestination? {
        guard let scrollView = pdfScrollView else { return currentDestination }

        let clipView = scrollView.contentView
        let visibleCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        let pointInPDFView = convert(visibleCenter, from: clipView)

        guard let page = page(for: pointInPDFView, nearest: true) else {
            return currentDestination
        }

        return PDFDestination(page: page, at: convert(pointInPDFView, to: page))
    }

    private struct PageState {
        var page: PDFPage
        var pageIndex: Int
        var pointOnPage: NSPoint
        var pageBounds: NSRect
    }

    private func currentPageState() -> PageState? {
        guard let document,
              let scrollView = pdfScrollView else { return nil }

        let clipView = scrollView.contentView
        let visibleCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        let pointInPDFView = convert(visibleCenter, from: clipView)

        guard let page = page(for: pointInPDFView, nearest: true) ?? currentPage else { return nil }

        return PageState(
            page: page,
            pageIndex: document.index(for: page),
            pointOnPage: convert(pointInPDFView, to: page),
            pageBounds: page.bounds(for: displayBox)
        )
    }

    private func topDestination(for page: PDFPage) -> PDFDestination {
        let bounds = page.bounds(for: displayBox)
        return PDFDestination(page: page, at: NSPoint(x: bounds.midX, y: bounds.maxY))
    }

    private func centerVertically(on destination: PDFDestination) {
        guard let page = destination.page,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView else {
            go(to: destination)
            return
        }

        let clipView = scrollView.contentView
        let pointInPDFView = convert(destination.point, from: page)
        let pointInDocument = convert(pointInPDFView, to: documentView)
        let documentSize = documentView.bounds.size
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let currentOrigin = clipView.bounds.origin
        let next = NSPoint(
            x: currentOrigin.x,
            y: centeredScrollCoordinate(
                point: pointInDocument.y,
                currentOrigin: currentOrigin.y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func centerBothAxes(on destination: PDFDestination) {
        guard let page = destination.page,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView else {
            go(to: destination)
            return
        }

        let clipView = scrollView.contentView
        let pointInPDFView = convert(destination.point, from: page)
        let pointInDocument = convert(pointInPDFView, to: documentView)
        let documentSize = documentView.bounds.size
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let currentOrigin = clipView.bounds.origin
        let next = NSPoint(
            x: centeredScrollCoordinate(
                point: pointInDocument.x,
                currentOrigin: currentOrigin.x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: centeredScrollCoordinate(
                point: pointInDocument.y,
                currentOrigin: currentOrigin.y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func nextScrollCoordinate(
        origin: CGFloat,
        delta: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard delta != 0 else { return origin }
        guard contentLength > viewportLength else { return origin }
        return min(max(0, origin + delta), maxValue)
    }

    private func restoredScrollCoordinate(
        origin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return origin }
        return min(max(0, origin), maxValue)
    }

    private enum VerticalEdge {
        case top
        case bottom
    }

    private func scrollToDocumentEdge(_ edge: VerticalEdge) {
        guard let scrollView = pdfScrollView else { return }

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let currentOrigin = clipView.bounds.origin
        let nextY: CGFloat

        if scrollView.documentView?.isFlipped == true {
            nextY = edge == .top ? 0 : maxY
        } else {
            nextY = edge == .top ? maxY : 0
        }

        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func centeredScrollCoordinate(
        point: CGFloat,
        currentOrigin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return currentOrigin }
        return min(max(0, point - viewportLength / 2), maxValue)
    }

    private var minimumZoomScale: CGFloat {
        minScaleFactor > 0 ? minScaleFactor : 0.1
    }

    private var maximumZoomScale: CGFloat {
        maxScaleFactor > minimumZoomScale ? maxScaleFactor : 8
    }

    private var pdfScrollView: NSScrollView? {
        findScrollView(in: self)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }
}

struct KeyboardCapture: NSViewRepresentable {
    weak var appState: AppState?

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.appState = appState
        DispatchQueue.main.async {
            view.focus()
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.appState = appState
        DispatchQueue.main.async {
            nsView.focus()
        }
    }
}

final class KeyCaptureView: NSView {
    weak var appState: AppState?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focus()
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }
        super.keyUp(with: event)
    }
}

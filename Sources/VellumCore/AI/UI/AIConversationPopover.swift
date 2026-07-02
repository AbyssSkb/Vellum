@preconcurrency import AppKit
import SwiftUI
import WebKit

enum AIConversationPopoverMetrics {
    static let width: CGFloat = AIExplanationPopoverMetrics.width
    static let maximumHeight: CGFloat = AIExplanationPopoverMetrics.maximumHeight
    static let composerTextMinimumHeight: CGFloat = 40
    static let composerOuterVerticalPadding: CGFloat = 16
    static let dividerHeight: CGFloat = 1

    static var minimumComposerHeight: CGFloat {
        composerHeight(forTextHeight: composerTextMinimumHeight)
    }

    static var minimumHeight: CGFloat {
        minimumComposerHeight
    }

    static var initialSize: NSSize {
        NSSize(width: width, height: minimumHeight)
    }

    static func normalizedComposerTextHeight(_ textHeight: CGFloat) -> CGFloat {
        min(
            maximumHeight - composerOuterVerticalPadding,
            max(composerTextMinimumHeight, ceil(textHeight))
        )
    }

    static func composerHeight(forTextHeight textHeight: CGFloat) -> CGFloat {
        normalizedComposerTextHeight(textHeight) + composerOuterVerticalPadding
    }
}

@MainActor
final class AIConversationPopoverModel: ObservableObject {
    @Published var messages: [AIConversationMessage] = [] {
        didSet {
            measuredMessageContentHeight = nil
        }
    }
    @Published var draft = ""
    @Published var isSending = false
    @Published var requestStatus: AIRequestVisualStatus = .idle
    @Published var errorMessage: String? {
        didSet {
            measuredMessageContentHeight = nil
        }
    }
    @Published private(set) var composerTextHeight = AIConversationPopoverMetrics.composerTextMinimumHeight
    @Published private(set) var preferredHeight = AIConversationPopoverMetrics.minimumHeight
    private var measuredMessageContentHeight: CGFloat?
    let historyID: UUID
    let context: AIExplanationContext

    init(context: AIExplanationContext, historyID: UUID = UUID()) {
        self.context = context
        self.historyID = historyID
    }

    var selectedTextTitle: String {
        context.selectedText.aiPopoverTitle
    }

    var contextWindowText: String {
        [
            "File: \(context.fileName)",
            "Pages: \(context.pageNumbers.map(String.init).joined(separator: ", "))",
            "Selected: \(context.selectedText)",
            "Current: \(context.currentParagraph ?? context.nearbyText)"
        ]
        .joined(separator: "\n\n")
    }

    func appendToLatestAssistant(_ chunk: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else {
            messages.append(AIConversationMessage(role: .assistant, content: chunk))
            return
        }

        messages[lastIndex].content += chunk
    }

    func replaceLatestAssistant(with text: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else {
            messages.append(AIConversationMessage(role: .assistant, content: text))
            return
        }

        messages[lastIndex].content = text
    }

    var preferredSize: NSSize {
        NSSize(width: AIConversationPopoverMetrics.width, height: preferredHeight)
    }

    var composerHeight: CGFloat {
        AIConversationPopoverMetrics.composerHeight(forTextHeight: composerTextHeight)
    }

    var historyItem: AIConversationHistoryItem {
        AIConversationHistoryItem(
            id: historyID,
            context: context,
            messages: messages,
            updatedAt: Date()
        )
    }

    @discardableResult
    func updateComposerTextHeight(_ textHeight: CGFloat) -> Bool {
        let normalizedHeight = AIConversationPopoverMetrics.normalizedComposerTextHeight(textHeight)
        guard abs(composerTextHeight - normalizedHeight) > 0.5 else { return false }

        composerTextHeight = normalizedHeight
        return recalculatePreferredHeight()
    }

    @discardableResult
    func updateMessageContentHeight(_ contentHeight: CGFloat) -> Bool {
        measuredMessageContentHeight = max(0, ceil(contentHeight))
        return recalculatePreferredHeight()
    }

    @discardableResult
    private func updateContentHeight(_ contentHeight: CGFloat) -> Bool {
        let clampedHeight = min(
            AIConversationPopoverMetrics.maximumHeight,
            max(composerHeight, ceil(contentHeight))
        )

        guard abs(preferredHeight - clampedHeight) > 1 else { return false }
        preferredHeight = clampedHeight
        return true
    }

    @discardableResult
    func refreshPreferredHeight() -> Bool {
        recalculatePreferredHeight()
    }

    @discardableResult
    private func recalculatePreferredHeight() -> Bool {
        let messageContentHeight = currentMessageContentHeight()
        let totalHeight = messageContentHeight > 0
            ? messageContentHeight
                + AIConversationPopoverMetrics.dividerHeight
                + composerHeight
            : composerHeight

        return updateContentHeight(totalHeight)
    }

    private func currentMessageContentHeight() -> CGFloat {
        if let measuredMessageContentHeight {
            return measuredMessageContentHeight
        }

        return Self.estimatedMessageContentHeight(messages: messages, errorMessage: errorMessage)
    }

    private static func estimatedMessageContentHeight(
        messages: [AIConversationMessage],
        errorMessage: String?
    ) -> CGFloat {
        guard !messages.isEmpty || errorMessage != nil else {
            return 0
        }

        var messageHeights = messages.map(estimatedMessageHeight)
        if let errorMessage {
            messageHeights.append(estimatedTextHeight(errorMessage, charactersPerLine: 54) + 18)
        }

        let spacing = CGFloat(max(0, messageHeights.count - 1)) * 14
        return 28 + messageHeights.reduce(0, +) + spacing
    }

    private static func estimatedMessageHeight(_ message: AIConversationMessage) -> CGFloat {
        switch message.role {
        case .user:
            return estimatedTextHeight(message.content, charactersPerLine: 38) + 18
        case .assistant:
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return 20 }

            let lines = trimmed.components(separatedBy: .newlines)
            let estimatedLines = lines.reduce(0) { partialResult, line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { return partialResult + 1 }
                let charactersPerLine = trimmedLine.hasPrefix("```") ? 46 : 56
                return partialResult + max(1, Int(ceil(Double(trimmedLine.count) / Double(charactersPerLine))))
            }
            let headingCount = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.count
            let listCount = lines.filter { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                return trimmedLine.hasPrefix("- ")
                    || trimmedLine.hasPrefix("* ")
                    || trimmedLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
            }.count
            return CGFloat(max(1, estimatedLines)) * 20
                + CGFloat(headingCount) * 4
                + CGFloat(listCount) * 2
        }
    }

    private static func estimatedTextHeight(_ text: String, charactersPerLine: Int) -> CGFloat {
        let lines = text.components(separatedBy: .newlines)
        let estimatedLines = lines.reduce(0) { partialResult, line in
            partialResult + max(1, Int(ceil(Double(max(1, line.count)) / Double(charactersPerLine))))
        }
        return CGFloat(max(1, estimatedLines)) * 19
    }
}

struct AIConversationPopoverView: View {
    @Environment(\.appUILanguage) private var language
    @ObservedObject var model: AIConversationPopoverModel
    let onDismiss: () -> Void
    let onSend: (String) -> Void
    let onPreferredSizeChange: (NSSize) -> Void
    @State private var inputIsFocused = true
    @State private var inputFocusGeneration = 0

    var body: some View {
        visibleContent
        .frame(width: AIConversationPopoverMetrics.width, height: model.preferredHeight)
        .background(TokyoNight.panelElevatedColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(TokyoNight.foregroundColor)
        .overlay(alignment: .topLeading) {
            if model.requestStatus != .idle {
                AIRequestStatusIndicator(status: model.requestStatus)
                    .padding(8)
            }
        }
        .onChange(of: model.preferredHeight) { _, _ in
            onPreferredSizeChange(model.preferredSize)
        }
        .onChange(of: model.errorMessage) { _, _ in
            applyFallbackHeightIfNeeded()
        }
        .onChange(of: model.isSending) { _, _ in
            refocusInput()
        }
        .onAppear {
            DispatchQueue.main.async {
                refocusInput()
                applyFallbackHeightIfNeeded()
                onPreferredSizeChange(model.preferredSize)
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    private var hasConversationContent: Bool {
        !model.messages.isEmpty || model.errorMessage != nil
    }

    private var messageViewportHeight: CGFloat {
        guard hasConversationContent else { return 0 }
        return max(
            0,
            model.preferredHeight
                - model.composerHeight
                - AIConversationPopoverMetrics.dividerHeight
        )
    }

    private var visibleContent: some View {
        VStack(spacing: 0) {
            if hasConversationContent {
                messagesView
                TokyoNightDivider(axis: .horizontal)
            }

            composer
        }
    }

    private var messagesView: some View {
        AIConversationTranscriptWebView(
            messages: model.messages,
            errorMessage: model.errorMessage,
            isSending: model.isSending,
            thinkingText: language.text(.aiChatThinking),
            onDismiss: onDismiss,
            onContentHeightChange: applyMeasuredContentHeight
        )
        .frame(height: messageViewportHeight)
        .background(TokyoNight.panelColor.opacity(0.22))
        .onChange(of: model.messages) { _, _ in
            refocusInput()
        }
        .onChange(of: model.preferredHeight) { _, _ in
            refocusInput()
        }
        .onChange(of: model.isSending) { _, _ in
            refocusInput()
        }
    }

    private var composer: some View {
        ZStack(alignment: .bottomTrailing) {
            AIConversationInputTextView(
                text: $model.draft,
                isFocused: $inputIsFocused,
                focusGeneration: inputFocusGeneration,
                onHeightChange: applyMeasuredComposerTextHeight,
                onSubmit: sendDraft
            )
            .frame(height: model.composerTextHeight)
            .padding(.leading, 12)
            .padding(.trailing, 42)

            if model.draft.isEmpty {
                Text(language.text(.aiChatPlaceholder))
                    .font(.system(size: 13))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .padding(.top, 11)
                    .padding(.leading, 12)
                    .padding(.trailing, 42)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Button {
                sendDraft()
            } label: {
                Image(systemName: model.isSending ? "hourglass" : "arrow.up")
                    .font(.system(size: 11.5, weight: .bold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AIConversationSendButtonStyle())
            .focusable(false)
            .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(language.text(.aiChatSend))
            .padding(.trailing, 7)
            .padding(.bottom, 7)
        }
        .frame(height: model.composerTextHeight)
        .background(TokyoNight.backgroundDeepColor.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    inputIsFocused ? TokyoNight.cyanColor.opacity(0.94) : TokyoNight.borderColor.opacity(0.62),
                    lineWidth: inputIsFocused ? 1.5 : 1
                )
        }
        .shadow(color: inputIsFocused ? TokyoNight.cyanColor.opacity(0.16) : .clear, radius: 7, y: 0)
        .contentShape(Rectangle())
        .onTapGesture {
            refocusInput()
        }
        .padding(8)
        .frame(height: model.composerHeight)
        .background(TokyoNight.panelElevatedColor)
    }

    private func sendDraft() {
        guard !model.isSending else { return }
        let prompt = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        model.draft = ""
        refocusInput()
        onSend(prompt)
        DispatchQueue.main.async {
            refocusInput()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            refocusInput()
        }
    }

    private func refocusInput() {
        inputIsFocused = true
        inputFocusGeneration += 1
    }

    private func applyFallbackHeightIfNeeded() {
        guard hasConversationContent,
              model.preferredHeight <= AIConversationPopoverMetrics.minimumHeight + 1 else { return }

        if model.refreshPreferredHeight() {
            onPreferredSizeChange(model.preferredSize)
        }
    }

    private func applyMeasuredContentHeight(_ messageContentHeight: CGFloat) {
        guard hasConversationContent, messageContentHeight > 0 else { return }
        if model.updateMessageContentHeight(messageContentHeight) {
            onPreferredSizeChange(model.preferredSize)
        }
    }

    private func applyMeasuredComposerTextHeight(_ textHeight: CGFloat) {
        if model.updateComposerTextHeight(textHeight) {
            onPreferredSizeChange(model.preferredSize)
        }
    }

}

private struct AIConversationInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusGeneration: Int
    let onHeightChange: (CGFloat) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        let textView = AIConversationNSTextView()
        textView.delegate = context.coordinator
        textView.onCommandReturn = onSubmit
        textView.shouldFocusWhenAttached = isFocused
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = TokyoNight.foreground
        textView.insertionPointColor = TokyoNight.foreground
        textView.textContainerInset = NSSize(width: 0, height: 11)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 40)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.selectedTextAttributes = [
            .backgroundColor: TokyoNight.selection,
            .foregroundColor: TokyoNight.foreground
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AIConversationNSTextView else { return }
        textView.onCommandReturn = onSubmit
        textView.shouldFocusWhenAttached = isFocused
        context.coordinator.onHeightChange = onHeightChange
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.reportTextHeight(in: scrollView)

        if textView.window?.firstResponder === textView, !isFocused {
            DispatchQueue.main.async {
                isFocused = true
            }
        }

        let shouldRefocus = isFocused
            && (context.coordinator.focusGeneration != focusGeneration || textView.window?.firstResponder !== textView)
        context.coordinator.focusGeneration = focusGeneration

        if shouldRefocus {
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.focusAndShowInsertionPoint()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        var onHeightChange: (CGFloat) -> Void
        var focusGeneration = 0
        private var lastReportedHeight: CGFloat?
        weak var textView: NSTextView?

        init(text: Binding<String>, isFocused: Binding<Bool>, onHeightChange: @escaping (CGFloat) -> Void) {
            _text = text
            _isFocused = isFocused
            self.onHeightChange = onHeightChange
            super.init()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            reportTextHeight(in: textView.enclosingScrollView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? AIConversationNSTextView else { return }
            guard textView.window != nil else {
                isFocused = false
                return
            }

            isFocused = true
            DispatchQueue.main.async { [weak textView] in
                textView?.focusAndShowInsertionPoint()
            }
        }

        func reportTextHeight(in scrollView: NSScrollView?) {
            guard let scrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }

            let availableWidth = scrollView.contentSize.width
            guard availableWidth > 1 else { return }

            if abs(textView.frame.width - availableWidth) > 0.5 {
                textView.frame.size.width = availableWidth
            }

            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }

            textContainer.containerSize = NSSize(
                width: availableWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)

            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let measuredHeight = ceil(usedHeight + textView.textContainerInset.height * 2 + 1)
            let normalizedHeight = AIConversationPopoverMetrics.normalizedComposerTextHeight(measuredHeight)
            let documentHeight = max(normalizedHeight, scrollView.contentSize.height)
            if abs(textView.frame.height - documentHeight) > 0.5 {
                textView.frame.size.height = documentHeight
            }

            guard lastReportedHeight.map({ abs($0 - normalizedHeight) > 0.5 }) ?? true else { return }
            lastReportedHeight = normalizedHeight
            onHeightChange(normalizedHeight)
        }
    }
}

private final class AIConversationNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var shouldFocusWhenAttached = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard shouldFocusWhenAttached, window != nil else { return }

        DispatchQueue.main.async { [weak self] in
            self?.focusAndShowInsertionPoint()
        }
    }

    func focusAndShowInsertionPoint() {
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        scrollRangeToVisible(selectedRange())
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let commandModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        let shouldSend = isReturn
            && event.modifierFlags.intersection(commandModifiers).isEmpty
            && !event.modifierFlags.contains(.shift)

        guard shouldSend else {
            super.keyDown(with: event)
            return
        }

        onCommandReturn?()
        DispatchQueue.main.async { [weak self] in
            self?.focusAndShowInsertionPoint()
        }
    }
}

private struct AIConversationTranscriptWebView: NSViewRepresentable {
    let messages: [AIConversationMessage]
    let errorMessage: String?
    let isSending: Bool
    let thinkingText: String
    let onDismiss: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> AIConversationTranscriptWKWebView {
        let webView = AIConversationTranscriptWKWebView()
        webView.onDismiss = onDismiss
        webView.onContentHeightChange = onContentHeightChange
        webView.render(messages: messages, errorMessage: errorMessage, isSending: isSending, thinkingText: thinkingText)
        return webView
    }

    func updateNSView(_ webView: AIConversationTranscriptWKWebView, context: Context) {
        webView.onDismiss = onDismiss
        webView.onContentHeightChange = onContentHeightChange
        webView.render(messages: messages, errorMessage: errorMessage, isSending: isSending, thinkingText: thinkingText)
    }
}

private final class AIConversationTranscriptWKWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    var onDismiss: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    private var pendingPayload = "[]"
    private var pendingFollowBottom = true
    private var didLoadDocument = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "vellumConversation")
        setValue(false, forKey: "drawsBackground")
        loadHTMLString(AIConversationTranscriptHTML.document, baseURL: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" else {
            super.keyDown(with: event)
            return
        }

        onDismiss?()
    }

    func render(messages: [AIConversationMessage], errorMessage: String?, isSending: Bool, thinkingText: String) {
        pendingPayload = Self.javascriptLiteral(
            messages.map { message in
                [
                    "id": message.id.uuidString,
                    "role": message.role.rawValue,
                    "content": message.content
                ]
            },
            errorMessage: errorMessage,
            isSending: isSending,
            thinkingText: thinkingText
        )
        pendingFollowBottom = true
        guard didLoadDocument else { return }
        evaluateJavaScript("window.vellumSetConversation(\(pendingPayload), \(pendingFollowBottom ? "true" : "false"));")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoadDocument = true
        evaluateJavaScript("window.vellumSetConversation(\(pendingPayload), true);")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vellumConversation",
              let payload = message.body as? [String: Any],
              let command = payload["command"] as? String,
              command == "contentHeight",
              let height = payload["height"] as? NSNumber else { return }
        onContentHeightChange?(CGFloat(truncating: height))
    }

    private static func javascriptLiteral(
        _ messages: [[String: String]],
        errorMessage: String?,
        isSending: Bool,
        thinkingText: String
    ) -> String {
        var payload: [String: Any] = [
            "messages": messages,
            "isSending": isSending,
            "thinkingText": thinkingText
        ]
        if let errorMessage {
            payload["errorMessage"] = errorMessage
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"messages":[],"isSending":false}"#
        }
        return string
    }
}

private struct AIConversationSendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? TokyoNight.backgroundDeepColor : TokyoNight.mutedColor)
            .background(
                isEnabled
                    ? TokyoNight.cyanColor.opacity(configuration.isPressed ? 0.72 : 0.92)
                    : TokyoNight.panelColor.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isEnabled ? TokyoNight.cyanColor.opacity(0.58) : TokyoNight.borderColor.opacity(0.48), lineWidth: 1)
            }
    }
}

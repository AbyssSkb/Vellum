@preconcurrency import AppKit
import SwiftUI

enum AIConversationPopoverMetrics {
    static let width: CGFloat = AIExplanationPopoverMetrics.width
    static let minimumHeight: CGFloat = 56
    static let maximumHeight: CGFloat = AIExplanationPopoverMetrics.maximumHeight
    static let composerHeight: CGFloat = 56
    static let dividerHeight: CGFloat = 1

    static var initialSize: NSSize {
        NSSize(width: width, height: minimumHeight)
    }
}

@MainActor
final class AIConversationPopoverModel: ObservableObject {
    @Published var messages: [AIConversationMessage] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published var requestStatus: AIRequestVisualStatus = .idle
    @Published var errorMessage: String?
    @Published private(set) var preferredHeight = AIConversationPopoverMetrics.minimumHeight
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

    var historyItem: AIConversationHistoryItem {
        AIConversationHistoryItem(
            id: historyID,
            context: context,
            messages: messages,
            updatedAt: Date()
        )
    }

    @discardableResult
    func updateContentHeight(_ contentHeight: CGFloat) -> Bool {
        let clampedHeight = min(
            AIConversationPopoverMetrics.maximumHeight,
            max(AIConversationPopoverMetrics.minimumHeight, ceil(contentHeight))
        )

        guard abs(preferredHeight - clampedHeight) > 1 else { return false }
        preferredHeight = clampedHeight
        return true
    }

    @discardableResult
    func refreshPreferredHeight() -> Bool {
        updateContentHeight(
            Self.estimatedContentHeight(messages: messages, errorMessage: errorMessage)
        )
    }

    private static func estimatedContentHeight(
        messages: [AIConversationMessage],
        errorMessage: String?
    ) -> CGFloat {
        guard !messages.isEmpty || errorMessage != nil else {
            return AIConversationPopoverMetrics.minimumHeight
        }

        var messageHeights = messages.map(estimatedMessageHeight)
        if let errorMessage {
            messageHeights.append(estimatedTextHeight(errorMessage, charactersPerLine: 54) + 18)
        }

        let spacing = CGFloat(max(0, messageHeights.count - 1)) * 14
        let messageAreaHeight = 28 + messageHeights.reduce(0, +) + spacing
        return messageAreaHeight
            + AIConversationPopoverMetrics.dividerHeight
            + AIConversationPopoverMetrics.composerHeight
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
    private let bottomAnchorID = "bottom"

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
        .onPreferenceChange(AIConversationMessageContentHeightKey.self) { height in
            applyMeasuredContentHeight(height)
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
                - AIConversationPopoverMetrics.composerHeight
                - AIConversationPopoverMetrics.dividerHeight
        )
    }

    private var visibleContent: some View {
        VStack(spacing: 0) {
            if hasConversationContent {
                messageMeasurementView
                messagesView
                TokyoNightDivider(axis: .horizontal)
            }

            composer
        }
    }

    private var messageMeasurementView: some View {
        messageStack
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: AIConversationPopoverMetrics.width, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AIConversationMessageContentHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .hidden()
            .frame(height: 0)
            .clipped()
            .accessibilityHidden(true)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                messageStack
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .id(bottomAnchorID)
            }
            .frame(height: messageViewportHeight)
            .background(TokyoNight.panelColor.opacity(0.22))
            .onChange(of: model.messages) { _, _ in
                scrollToBottom(proxy)
                refocusInput()
            }
            .onChange(of: model.preferredHeight) { _, _ in
                scrollToBottom(proxy)
                refocusInput()
            }
            .onChange(of: model.isSending) { _, _ in
                scrollToBottom(proxy)
                refocusInput()
            }
        }
    }

    private var messageStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.messages) { message in
                AIConversationMessageRow(message: message)
                    .id(message.id)
            }

            if let errorMessage = model.errorMessage {
                AIConversationErrorRow(message: errorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        ZStack(alignment: .trailing) {
            AIConversationInputTextView(
                text: $model.draft,
                isFocused: $inputIsFocused,
                focusGeneration: inputFocusGeneration,
                onSubmit: sendDraft
            )
            .frame(height: 40)
            .padding(.leading, 12)
            .padding(.trailing, 42)

            if model.draft.isEmpty {
                Text(language.text(.aiChatPlaceholder))
                    .font(.system(size: 13))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .padding(.leading, 12)
                    .padding(.trailing, 42)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .frame(height: 40)
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
        .frame(height: AIConversationPopoverMetrics.composerHeight)
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
        let measuredHeight = messageContentHeight
            + AIConversationPopoverMetrics.dividerHeight
            + AIConversationPopoverMetrics.composerHeight
        if model.updateContentHeight(measuredHeight) {
            onPreferredSizeChange(model.preferredSize)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        func align() {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }

        DispatchQueue.main.async {
            align()
            DispatchQueue.main.async {
                align()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                align()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                align()
            }
        }
    }
}

private struct AIConversationMessageContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AIConversationInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusGeneration: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
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
        if textView.string != text {
            textView.string = text
        }

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

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        var focusGeneration = 0
        weak var textView: NSTextView?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
            super.init()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
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

private struct AIConversationMessageRow: View {
    let message: AIConversationMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 68)
                Text(message.content)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(TokyoNight.foregroundColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(TokyoNight.selectionColor.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TokyoNight.blueColor.opacity(0.34), lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant:
            AIConversationAssistantMessage(content: message.content)
        }
    }
}

private struct AIConversationAssistantMessage: View {
    @Environment(\.appUILanguage) private var language
    let content: String

    var body: some View {
        Group {
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(language.text(.aiChatThinking))
                    .font(.system(size: 13))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .italic()
            } else {
                AIConversationMarkdownView(markdown: content)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIConversationErrorRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(TokyoNight.redColor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TokyoNight.redColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.redColor.opacity(0.38), lineWidth: 1)
            }
    }
}

private struct AIConversationMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(AIConversationMarkdownParser.blocks(from: markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AIConversationMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            AIConversationMarkdownText(text, size: level == 1 ? 15 : 14, weight: .semibold)
                .foregroundStyle(TokyoNight.foregroundColor)
                .padding(.top, level == 1 ? 2 : 0)

        case .paragraph(let text):
            AIConversationMarkdownText(text, size: 13, weight: .regular)
                .lineSpacing(2)
                .foregroundStyle(TokyoNight.foregroundColor)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AIConversationListItem(marker: "•", text: item)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    AIConversationListItem(marker: "\(index + 1).", text: item)
                }
            }

        case .blockquote(let text):
            AIConversationMarkdownText(text, size: 12.5, weight: .regular)
                .lineSpacing(2)
                .foregroundStyle(TokyoNight.mutedColor)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(TokyoNight.blueColor.opacity(0.55))
                        .frame(width: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                }

        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(TokyoNight.cyanColor)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(TokyoNight.backgroundDeepColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.56), lineWidth: 1)
            }
        }
    }
}

private struct AIConversationMarkdownText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight

    init(_ text: String, size: CGFloat, weight: Font.Weight) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Text(attributedText)
            .font(.system(size: size, weight: weight))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            return AttributedString(text)
        }
    }
}

private struct AIConversationListItem: View {
    let marker: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 18, alignment: .trailing)

            AIConversationMarkdownText(text, size: 13, weight: .regular)
                .lineSpacing(2)
                .foregroundStyle(TokyoNight.foregroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AIConversationMarkdownBlock {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case blockquote(String)
        case code(String)
    }

    let kind: Kind
}

private enum AIConversationMarkdownParser {
    static func blocks(from markdown: String) -> [AIConversationMarkdownBlock] {
        var blocks: [AIConversationMarkdownBlock] = []
        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(AIConversationMarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: "\n"))))
            paragraphLines.removeAll()
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            blocks.append(AIConversationMarkdownBlock(kind: .unorderedList(unorderedItems)))
            unorderedItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            blocks.append(AIConversationMarkdownBlock(kind: .orderedList(orderedItems)))
            orderedItems.removeAll()
        }

        func flushInlineBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(AIConversationMarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                    isInCodeBlock = false
                } else {
                    flushInlineBlocks()
                    isInCodeBlock = true
                }
                continue
            }

            if isInCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            guard !line.isEmpty else {
                flushInlineBlocks()
                continue
            }

            if let heading = heading(from: line) {
                flushInlineBlocks()
                blocks.append(AIConversationMarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
            } else if let item = unorderedItem(from: line) {
                flushParagraph()
                flushOrderedList()
                unorderedItems.append(item)
            } else if let item = orderedItem(from: line) {
                flushParagraph()
                flushUnorderedList()
                orderedItems.append(item)
            } else if line.hasPrefix("> ") {
                flushInlineBlocks()
                blocks.append(AIConversationMarkdownBlock(kind: .blockquote(String(line.dropFirst(2)))))
            } else {
                flushUnorderedList()
                flushOrderedList()
                paragraphLines.append(line)
            }
        }

        if isInCodeBlock {
            blocks.append(AIConversationMarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
        }
        flushInlineBlocks()
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...3).contains(markerCount),
              line.dropFirst(markerCount).first == " " else { return nil }
        let text = line.dropFirst(markerCount + 1).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (markerCount, text)
    }

    private static func unorderedItem(from line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let remainder = line[line.index(after: dotIndex)...]
        guard remainder.first == " " else { return nil }
        return String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
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

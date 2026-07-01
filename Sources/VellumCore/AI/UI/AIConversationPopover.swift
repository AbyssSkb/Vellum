import SwiftUI

enum AIConversationPopoverMetrics {
    static let size = CGSize(width: 620, height: 520)
}

@MainActor
final class AIConversationPopoverModel: ObservableObject {
    @Published var messages: [AIConversationMessage] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    let context: AIExplanationContext

    init(context: AIExplanationContext) {
        self.context = context
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
}

struct AIConversationPopoverView: View {
    @Environment(\.appUILanguage) private var language
    @ObservedObject var model: AIConversationPopoverModel
    let onDismiss: () -> Void
    let onSend: (String) -> Void
    @FocusState private var inputIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messagesView
            composer
        }
        .frame(width: AIConversationPopoverMetrics.size.width, height: AIConversationPopoverMetrics.size.height)
        .background(TokyoNight.panelElevatedColor)
        .foregroundStyle(TokyoNight.foregroundColor)
        .onAppear {
            DispatchQueue.main.async {
                inputIsFocused = true
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.messages.isEmpty {
                        emptyState
                    }

                    ForEach(model.messages) { message in
                        AIConversationMessageRow(message: message)
                            .id(message.id)
                    }

                    if let errorMessage = model.errorMessage {
                        AIConversationErrorRow(message: errorMessage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .background(TokyoNight.panelColor.opacity(0.28))
            .onChange(of: model.messages) { _, messages in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        Text(model.selectedTextTitle)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundStyle(TokyoNight.mutedColor)
            .textSelection(.enabled)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TokyoNight.backgroundDeepColor.opacity(0.36), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(TokyoNight.cyanColor.opacity(0.42))
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            TokyoNightDivider(axis: .horizontal)

            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.draft)
                        .font(.system(size: 13))
                        .foregroundStyle(TokyoNight.foregroundColor)
                        .scrollContentBackground(.hidden)
                        .focused($inputIsFocused)
                        .padding(.trailing, 36)
                        .padding(.bottom, 22)

                    if model.draft.isEmpty {
                        Text(language.text(.aiChatPlaceholder))
                            .font(.system(size: 13))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(height: 92)
                .background(TokyoNight.backgroundDeepColor.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(inputIsFocused ? TokyoNight.cyanColor.opacity(0.58) : TokyoNight.borderColor.opacity(0.62), lineWidth: 1)
                }

                Button {
                    sendDraft()
                } label: {
                    Image(systemName: model.isSending ? "hourglass" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AIConversationSendButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(language.text(.aiChatSend))
                .padding(8)
            }
            .padding(12)
            .background(TokyoNight.panelElevatedColor)
        }
    }

    private func sendDraft() {
        let prompt = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        model.draft = ""
        onSend(prompt)
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

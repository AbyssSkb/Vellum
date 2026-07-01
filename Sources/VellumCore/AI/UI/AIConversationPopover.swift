import SwiftUI

enum AIConversationPopoverMetrics {
    static let size = CGSize(width: 620, height: 560)
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
            header
            TokyoNightDivider(axis: .horizontal)
            contextPanel
            TokyoNightDivider(axis: .horizontal)
            messagesView
            composer
        }
        .frame(width: AIConversationPopoverMetrics.size.width, height: AIConversationPopoverMetrics.size.height)
        .background(TokyoNight.panelElevatedColor)
        .foregroundStyle(TokyoNight.foregroundColor)
        .onAppear {
            inputIsFocused = true
        }
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor)
                .frame(width: 30, height: 30)
                .background(TokyoNight.backgroundDeepColor.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(.aiConversation))
                    .font(.system(size: 14, weight: .semibold))
                Text(model.selectedTextTitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AIConversationIconButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(language.text(.aiChatContext), systemImage: "text.viewfinder")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor)

            ScrollView(.vertical, showsIndicators: true) {
                Text(model.contextWindowText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TokyoNight.foregroundColor.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(height: 126)
        .background(TokyoNight.backgroundDeepColor.opacity(0.48))
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { message in
                        AIConversationMessageRow(message: message)
                            .id(message.id)
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(TokyoNight.redColor)
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
                .padding(12)
            }
            .background(TokyoNight.panelColor.opacity(0.35))
            .onChange(of: model.messages) { _, messages in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: $model.draft)
                .font(.system(size: 12.5))
                .foregroundStyle(TokyoNight.foregroundColor)
                .scrollContentBackground(.hidden)
                .background(TokyoNight.backgroundDeepColor.opacity(0.74), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(inputIsFocused ? TokyoNight.cyanColor.opacity(0.62) : TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
                }
                .focused($inputIsFocused)
                .frame(height: 72)
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text(language.text(.aiChatPlaceholder))
                            .font(.system(size: 12.5))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                sendDraft()
            } label: {
                Label(
                    model.isSending ? language.text(.aiChatThinking) : language.text(.aiChatSend),
                    systemImage: model.isSending ? "hourglass" : "paperplane.fill"
                )
                .frame(minWidth: 82)
            }
            .buttonStyle(AIConversationSendButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(TokyoNight.panelElevatedColor)
    }

    private func sendDraft() {
        let prompt = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        model.draft = ""
        onSend(prompt)
    }
}

private struct AIConversationMessageRow: View {
    @Environment(\.appUILanguage) private var language
    let message: AIConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(message.role == .user ? TokyoNight.blueColor : TokyoNight.cyanColor)
                Text(message.role == .user ? language.text(.aiChatUser) : language.text(.aiChatAssistant))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TokyoNight.mutedColor)
            }

            Text(message.content.isEmpty ? language.text(.aiChatThinking) : message.content)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(TokyoNight.foregroundColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        }
    }

    private var background: Color {
        message.role == .user
            ? TokyoNight.selectionColor.opacity(0.36)
            : TokyoNight.backgroundDeepColor.opacity(0.62)
    }

    private var stroke: Color {
        message.role == .user
            ? TokyoNight.blueColor.opacity(0.35)
            : TokyoNight.borderColor.opacity(0.48)
    }
}

private struct AIConversationIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? TokyoNight.cyanColor : TokyoNight.mutedColor)
            .background(
                TokyoNight.backgroundDeepColor.opacity(configuration.isPressed ? 0.9 : 0.54),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

private struct AIConversationSendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isEnabled ? TokyoNight.backgroundDeepColor : TokyoNight.mutedColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                isEnabled
                    ? TokyoNight.cyanColor.opacity(configuration.isPressed ? 0.72 : 0.9)
                    : TokyoNight.backgroundDeepColor.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isEnabled ? TokyoNight.cyanColor.opacity(0.58) : TokyoNight.borderColor.opacity(0.45), lineWidth: 1)
            }
    }
}

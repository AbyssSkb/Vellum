@preconcurrency import AppKit
import SwiftUI

struct AIConversationHistorySwitcherOverlay: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AIHistorySwitcherOverlay(
            mode: .conversation,
            items: appState.aiConversationHistory.map(AIHistorySwitcherItem.init),
            onDismiss: appState.hideAIConversationHistory,
            onOpen: { item in
                guard let historyItem = appState.aiConversationHistory.first(where: { $0.id == item.id }) else { return }
                appState.restoreAIConversation(historyItem)
            }
        )
    }
}

struct AIExplanationHistorySwitcherOverlay: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AIHistorySwitcherOverlay(
            mode: .explanation,
            items: appState.aiExplanationHistory.map(AIHistorySwitcherItem.init),
            onDismiss: appState.hideAIExplanationHistory,
            onOpen: { item in
                guard let historyItem = appState.aiExplanationHistory.first(where: { $0.id == item.id }) else { return }
                appState.restoreAIExplanation(historyItem)
            }
        )
    }
}

private struct AIHistorySwitcherOverlay: View {
    enum Mode {
        case conversation
        case explanation

        var systemImage: String {
            switch self {
            case .conversation: return "bubble.left.and.bubble.right"
            case .explanation: return "sparkles"
            }
        }

        func title(in language: AppUILanguage) -> String {
            switch self {
            case .conversation: return language.text(.aiConversationHistory)
            case .explanation: return language.text(.aiExplanationHistory)
            }
        }

        func placeholder(in language: AppUILanguage) -> String {
            switch self {
            case .conversation: return language.text(.searchAIConversations)
            case .explanation: return language.text(.searchAIExplanations)
            }
        }

        func emptyText(in language: AppUILanguage) -> String {
            switch self {
            case .conversation: return language.text(.noMatchingAIConversations)
            case .explanation: return language.text(.noMatchingAIExplanations)
            }
        }
    }

    @Environment(\.appUILanguage) private var language
    let mode: Mode
    let items: [AIHistorySwitcherItem]
    let onDismiss: () -> Void
    let onOpen: (AIHistorySwitcherItem) -> Void
    @State private var query = ""
    @State private var selectedIndex = 0

    private var matches: [AIHistorySwitcherItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }

        return items.filter { item in
            item.searchableText.localizedCaseInsensitiveContains(term)
        }
    }

    private var listHeight: CGFloat {
        let visibleRows = matches.isEmpty ? 1 : min(matches.count, 6)
        return CGFloat(visibleRows) * AIHistorySwitcherRow.metricsHeight
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(TokyoNight.backgroundDeepColor.opacity(0.80))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                searchHeader

                Rectangle()
                    .fill(TokyoNight.borderColor.opacity(0.72))
                    .frame(height: 1)

                historyList
            }
            .frame(maxWidth: 620)
            .background {
                ZStack {
                    AIHistoryVisualEffectBackground()
                    TokyoNight.panelElevatedColor.opacity(0.86)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.95), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: matches.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedIndex = 0
                return
            }
            selectedIndex = min(selectedIndex, ids.count - 1)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor.opacity(0.95))
                .frame(width: 24, height: 24)

            AIHistorySearchField(
                text: $query,
                placeholder: mode.placeholder(in: language),
                onMoveUp: { moveSelection(.up) },
                onMoveDown: { moveSelection(.down) },
                onCommit: openSelectedMatch,
                onCancel: onDismiss
            )
            .frame(height: 34)

            matchCount
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(TokyoNight.panelColor.opacity(0.92))
    }

    private var matchCount: some View {
        Text("\(matches.count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(matches.isEmpty ? TokyoNight.redColor : TokyoNight.cyanColor)
            .frame(minWidth: 34, minHeight: 24)
            .padding(.horizontal, 8)
            .background(TokyoNight.backgroundDeepColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        matches.isEmpty
                            ? TokyoNight.redColor.opacity(0.42)
                            : TokyoNight.cyanColor.opacity(0.28),
                        lineWidth: 1
                    )
            }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if matches.isEmpty {
                        emptyRow
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                            AIHistorySwitcherRow(
                                item: item,
                                isSelected: index == selectedIndex
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onOpen(item)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: listHeight)
            .background(TokyoNight.panelElevatedColor.opacity(0.82))
            .onChange(of: selectedItemIDForScroll) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 22)

            Text(mode.emptyText(in: language))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TokyoNight.mutedColor)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: AIHistorySwitcherRow.metricsHeight)
    }

    private var selectedItemIDForScroll: AIHistorySwitcherItem.ID? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex].id
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !matches.isEmpty else { return }

        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(matches.count - 1, selectedIndex + 1)
        default:
            break
        }
    }

    private func openSelectedMatch() {
        guard matches.indices.contains(selectedIndex) else { return }
        onOpen(matches[selectedIndex])
    }
}

private struct AIHistorySwitcherItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let preview: String
    let searchableText: String

    init(_ item: AIConversationHistoryItem) {
        id = item.id
        title = item.selectedText.aiPopoverTitle
        preview = item.messages.last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.content
            ?? item.selectedText
        searchableText = item.searchableText
    }

    init(_ item: AIExplanationHistoryItem) {
        id = item.id
        title = item.selectedText.aiPopoverTitle
        preview = item.explanation
        searchableText = item.searchableText
    }
}

private struct AIHistorySwitcherRow: View {
    static let metricsHeight: CGFloat = 58
    let item: AIHistorySwitcherItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)
                    .lineLimit(1)

                Text(item.preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TokyoNight.foregroundColor.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.metricsHeight)
        .background(isSelected ? TokyoNight.selectionColor.opacity(0.82) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(TokyoNight.cyanColor)
                    .frame(width: 3)
            }
        }
    }
}

private struct AIHistorySearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> AIHistoryTextField {
        let textField = AIHistoryTextField()
        textField.delegate = context.coordinator
        textField.onMoveUp = onMoveUp
        textField.onMoveDown = onMoveDown
        textField.onCommit = onCommit
        textField.onCancel = onCancel
        textField.configure(placeholder: placeholder)
        focus(textField)
        return textField
    }

    func updateNSView(_ nsView: AIHistoryTextField, context: Context) {
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.configurePlaceholder(placeholder)

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.text = $text
        focus(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private func focus(_ textField: AIHistoryTextField) {
        DispatchQueue.main.async {
            guard textField.window?.firstResponder !== textField.currentEditor() else { return }
            textField.window?.makeFirstResponder(textField)
            textField.currentEditor()?.selectedRange = NSRange(location: textField.stringValue.count, length: 0)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let textField = control as? AIHistoryTextField else { return false }
            return textField.performCommand(commandSelector)
        }
    }
}

private struct AIHistoryVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .withinWindow
        nsView.state = .active
        nsView.isEmphasized = false
    }
}

private final class AIHistoryTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func configure(placeholder: String) {
        cell = AIHistoryTextFieldCell(textCell: "")
        font = .systemFont(ofSize: 22, weight: .medium)
        textColor = TokyoNight.foreground
        configurePlaceholder(placeholder)
        backgroundColor = .clear
        isBordered = false
        isBezeled = false
        drawsBackground = false
        isEditable = true
        isSelectable = true
        isEnabled = true
        focusRingType = .none
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
    }

    func configurePlaceholder(_ placeholder: String) {
        placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: TokyoNight.muted.withAlphaComponent(0.92),
                .font: NSFont.systemFont(ofSize: 22, weight: .regular)
            ]
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            onCancel?()
            return
        }

        switch event.specialKey {
        case .upArrow:
            onMoveUp?()
        case .downArrow:
            onMoveDown?()
        case .carriageReturn, .newline:
            onCommit?()
        default:
            super.keyDown(with: event)
        }
    }

    func performCommand(_ commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            onMoveUp?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            onMoveDown?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }
}

private final class AIHistoryTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        drawingRect.origin.y += max(0, (rect.height - textHeight) / 2)
        drawingRect.size.height = min(drawingRect.height, textHeight)
        return drawingRect
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

@preconcurrency import AppKit
import SwiftUI

struct TabSwitcherOverlay: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0

    private var matches: [PDFTab] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return appState.tabs }

        return appState.tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(term)
                || (tab.url?.lastPathComponent.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private var listHeight: CGFloat {
        let visibleRows = matches.isEmpty ? 1 : min(matches.count, 6)
        return CGFloat(visibleRows) * TabSwitcherRow.metricsHeight
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(TokyoNight.backgroundDeepColor.opacity(0.80))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.hideTabSwitcher()
                }

            VStack(spacing: 0) {
                searchHeader

                Rectangle()
                    .fill(TokyoNight.borderColor.opacity(0.72))
                    .frame(height: 1)

                tabList
            }
            .frame(maxWidth: 620)
            .background {
                ZStack {
                    TabSwitcherVisualEffectBackground()
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
        .onAppear {
            selectedIndex = selectedIndexForCurrentTab()
        }
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor.opacity(0.95))
                .frame(width: 24, height: 24)

            TabSwitcherSearchField(
                text: $query,
                language: language,
                onMoveUp: { moveSelection(.up) },
                onMoveDown: { moveSelection(.down) },
                onCommit: openSelectedMatch,
                onCancel: {
                    appState.hideTabSwitcher()
                }
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

    private var tabList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if matches.isEmpty {
                        emptyRow
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, tab in
                            TabSwitcherRow(
                                tab: tab,
                                isSelected: index == selectedIndex,
                                isCurrent: tab.id == appState.selectedTabID
                            )
                            .id(tab.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                open(tab)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: listHeight)
            .background(TokyoNight.panelElevatedColor.opacity(0.82))
            .onChange(of: selectedTabIDForScroll) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 22)

            Text(language.text(.noMatchingTabs))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TokyoNight.mutedColor)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var selectedTabIDForScroll: PDFTab.ID? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex].id
    }

    private func selectedIndexForCurrentTab() -> Int {
        guard let selectedTabID = appState.selectedTabID,
              let index = matches.firstIndex(where: { $0.id == selectedTabID }) else {
            return 0
        }
        return index
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
        open(matches[selectedIndex])
    }

    private func open(_ tab: PDFTab) {
        appState.selectTabFromSwitcher(tab.id)
    }
}

private struct TabSwitcherSearchField: NSViewRepresentable {
    @Binding var text: String
    let language: AppUILanguage
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> TabSwitcherTextField {
        let textField = TabSwitcherTextField()
        textField.delegate = context.coordinator
        textField.onMoveUp = onMoveUp
        textField.onMoveDown = onMoveDown
        textField.onCommit = onCommit
        textField.onCancel = onCancel
        textField.configure(language: language)
        focus(textField)
        return textField
    }

    func updateNSView(_ nsView: TabSwitcherTextField, context: Context) {
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.configurePlaceholder(language: language)

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.text = $text
        focus(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private func focus(_ textField: TabSwitcherTextField) {
        DispatchQueue.main.async {
            guard textField.window?.firstResponder !== textField.currentEditor() else { return }
            textField.window?.makeFirstResponder(textField)
            textField.currentEditor()?.selectedRange = NSRange(
                location: textField.stringValue.count,
                length: 0
            )
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
            guard let textField = control as? TabSwitcherTextField else { return false }
            return textField.performCommand(commandSelector)
        }
    }
}

private struct TabSwitcherVisualEffectBackground: NSViewRepresentable {
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

private final class TabSwitcherTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func configure(language: AppUILanguage) {
        cell = TabSwitcherTextFieldCell(textCell: "")
        font = .systemFont(ofSize: 22, weight: .medium)
        textColor = TokyoNight.foreground
        configurePlaceholder(language: language)
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

    func configurePlaceholder(language: AppUILanguage) {
        placeholderAttributedString = NSAttributedString(
            string: language.text(.searchOpenTabs),
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

private final class TabSwitcherTextFieldCell: NSTextFieldCell {
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

private struct TabSwitcherRow: View {
    @Environment(\.appUILanguage) private var language
    static let metricsHeight: CGFloat = 58
    let tab: PDFTab
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "doc.fill" : "doc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)
                    .lineLimit(1)

                Text(tab.url?.path ?? language.text(.untitled))
                    .font(.system(size: 11))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TokyoNight.cyanColor)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.metricsHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(TokyoNight.cyanColor)
                    .frame(width: 3)
            }
        }
    }

    private var iconColor: Color {
        if isSelected {
            return TokyoNight.cyanColor
        }
        return isCurrent ? TokyoNight.blueColor : TokyoNight.mutedColor
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(isSelected ? TokyoNight.selectionColor.opacity(0.82) : Color.clear)
    }
}

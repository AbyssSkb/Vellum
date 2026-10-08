@preconcurrency import AppKit
import SwiftUI

struct TabSwitcherOverlay: View {
    @Environment(\.appUILanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @StateObject private var previews = TabSwitcherPreviewStore()
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var isVisible = false
    @State private var isClosing = false
    @State private var isCancelHovered = false
    @State private var transitionTask: Task<Void, Never>?

    private var matches: [PDFTab] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return appState.tabs }
        return appState.tabs.filter {
            $0.title.localizedCaseInsensitiveContains(term)
                || ($0.url?.lastPathComponent.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private var selectedTab: PDFTab? {
        matches.indices.contains(selectedIndex) ? matches[selectedIndex] : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = TabSwitcherLayout(size: geometry.size)
            VStack(spacing: 20) {
                searchHeader
                HStack(spacing: 26) {
                    tabList
                        .frame(width: layout.listWidth)
                    pagePreview(layout: layout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(TokyoNight.borderColor.opacity(0.45)).frame(width: 1)
                        }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(layout.padding)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(TokyoNight.backgroundColor)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(!isClosing)
            .onAppear {
                selectedIndex = appState.tabs.firstIndex { $0.id == appState.selectedTabID } ?? 0
                updatePreviews(layout: layout)
                withAnimation(.easeOut(duration: 0.15)) { isVisible = true }
            }
            .onChange(of: query) { _, _ in
                select(0)
                updatePreviews(layout: layout)
            }
            .onChange(of: appState.tabs) { _, _ in
                selectedIndex = min(selectedIndex, max(0, matches.count - 1))
                if !isClosing { updatePreviews(layout: layout) }
            }
            .onChange(of: selectedIndex) { _, _ in updatePreviews(layout: layout) }
            .onChange(of: appState.selectedTabID) { _, _ in
                if !isClosing { appState.hideTabSwitcher() }
            }
            .onChange(of: geometry.size) { _, _ in
                if !isClosing { updatePreviews(layout: layout) }
            }
        }
        .onDisappear {
            transitionTask?.cancel()
            previews.cancel()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)
                .accessibilityHidden(true)
            TabSwitcherSearchField(
                text: $query, language: language,
                onMoveUp: { select(selectedIndex - 1) },
                onMoveDown: { select(selectedIndex + 1) },
                onCommit: { if let tab = selectedTab { dismiss(committing: tab) } },
                onCancel: { dismiss(committing: nil) }
            )
            .frame(height: 36)
            Text("\(matches.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(TokyoNight.mutedColor)
                .accessibilityHidden(true)
            Button { dismiss(committing: nil) } label: {
                Text("Esc")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isCancelHovered ? TokyoNight.foregroundColor : TokyoNight.mutedColor)
                    .frame(width: 32, height: 28)
                    .background(isCancelHovered ? TokyoNight.panelElevatedColor : TokyoNight.panelColor,
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(TokyoNight.borderColor, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isCancelHovered = $0 }
            .help(language.text(.cancel))
            .accessibilityLabel(language.text(.cancel))
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TokyoNight.borderColor.opacity(0.65)).frame(height: 1)
        }
    }

    private var tabList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if matches.isEmpty {
                        Text(language.text(.noMatchingTabs))
                            .font(.system(size: 13))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .padding(.horizontal, 14)
                    }
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, tab in
                        TabSwitcherRow(tab: tab, isSelected: index == selectedIndex,
                                       isCurrent: tab.id == appState.selectedTabID)
                            .id(tab.id)
                            .onTapGesture(count: 2) { dismiss(committing: tab) }
                            .onTapGesture { select(index) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { select(index) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { if let id = selectedTab?.id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: selectedTab?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func pagePreview(layout: TabSwitcherLayout) -> some View {
        VStack(spacing: 16) {
            ZStack {
                if let tab = selectedTab {
                    let size = layout.paperSize(for: tab)
                    paper(tab: tab)
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss(committing: tab) }
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { dismiss(committing: tab) }
                        .id(tab.id)
                        .transition(.opacity)
                }
            }
            .frame(width: layout.paperBox.width, height: layout.paperBox.height)
            .animation(.easeOut(duration: 0.14), value: selectedTab?.id)
            Group {
                if let tab = selectedTab, let document = tab.document, document.pageCount > 0 {
                    let index = min(max(tab.snapshot?.pageIndex ?? 0, 0), document.pageCount - 1)
                    Text("\(index + 1) / \(document.pageCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(TokyoNight.mutedColor)
                }
            }
            .frame(height: 16)
        }
    }

    @ViewBuilder
    private func paper(tab: PDFTab) -> some View {
        if let image = previews.images[tab.id] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        } else {
            RoundedRectangle(cornerRadius: 2).fill(TokyoNight.panelElevatedColor)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(TokyoNight.mutedColor.opacity(0.4))
                }
        }
    }

    private func select(_ index: Int) {
        guard !isClosing else { return }
        selectedIndex = min(max(index, 0), max(0, matches.count - 1))
    }

    private func updatePreviews(layout: TabSwitcherLayout) {
        let scale = appState.readerWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        previews.update(tabs: selectedTab.map { [$0] } ?? [], maximumPixelSize: NSSize(
            width: layout.paperBox.width * scale,
            height: layout.paperBox.height * scale
        ))
    }

    private func dismiss(committing tab: PDFTab?) {
        guard !isClosing else { return }
        isClosing = true
        if let tab { appState.selectTab(tab.id) }
        withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            appState.hideTabSwitcher()
        }
    }
}

private struct TabSwitcherLayout {
    let padding: CGFloat
    let listWidth: CGFloat
    let paperBox: CGSize

    init(size: CGSize) {
        padding = min(max(size.width * 0.036, 26), 40)
        let width = max(0, size.width - padding * 2)
        listWidth = min(360, max(0, width - 26) * 0.44)
        let paperWidth = max(0, width - listWidth - 26 - 40)
        paperBox = CGSize(width: paperWidth,
                          height: max(0, size.height - padding * 2 - 104))
    }

    func paperSize(for tab: PDFTab) -> CGSize {
        let index = min(max(tab.snapshot?.pageIndex ?? 0, 0), max(0, (tab.document?.pageCount ?? 1) - 1))
        let size = tab.document?.page(at: index).map { PDFPageDisplayGeometry(page: $0, box: .cropBox).bounds.size }
            ?? CGSize(width: 612, height: 792)
        let scale = min(paperBox.width / max(1, size.width), paperBox.height / max(1, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct TabSwitcherSearchField: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
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
        textField.canFocus = { [weak appState] in appState?.isTabSwitcherPresented == true }
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
        nsView.focusInitiallyIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
            guard !textView.hasMarkedText(), let textField = control as? TabSwitcherTextField else { return false }
            return textField.performCommand(commandSelector)
        }
    }
}

private final class TabSwitcherTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var canFocus: (() -> Bool)?
    private var needsInitialFocus = true

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusInitiallyIfNeeded()
    }

    func focusInitiallyIfNeeded() {
        guard needsInitialFocus, let window else { return }
        if let responder = window.firstResponder,
           responder === self || responder === currentEditor() {
            needsInitialFocus = false
            return
        }
        let expectedResponder = window.firstResponder
        DispatchQueue.main.async { [weak self, weak window, weak expectedResponder] in
            guard let self, let window, self.needsInitialFocus,
                  self.window === window, self.superview != nil,
                  self.canFocus?() == true,
                  NSApp.modalWindow == nil, window.attachedSheet == nil,
                  NSApp.keyWindow == nil || window.isKeyWindow else { return }
            self.needsInitialFocus = false
            guard window.firstResponder === expectedResponder else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectedRange = NSRange(location: self.stringValue.utf16.count, length: 0)
        }
    }

    func configure(language: AppUILanguage) {
        cell = TabSwitcherTextFieldCell(textCell: "")
        font = .systemFont(ofSize: 18, weight: .regular)
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
                .font: NSFont.systemFont(ofSize: 18, weight: .regular)
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
    let tab: PDFTab
    let isSelected: Bool
    let isCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? TokyoNight.foregroundColor : TokyoNight.foregroundColor.opacity(0.8))
                    .lineLimit(1)
                Text(tab.url?.deletingLastPathComponent().path ?? language.text(.untitled))
                    .font(.system(size: 11))
                    .foregroundStyle(TokyoNight.mutedColor.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TokyoNight.blueColor)
                    .help(language.text(.currentTab))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(isSelected ? TokyoNight.selectionColor.opacity(0.6)
                    : isHovered ? TokyoNight.panelElevatedColor.opacity(0.4) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(TokyoNight.blueColor).frame(width: 2, height: 14)
            }
        }
        .contentShape(Rectangle())
        .help(tab.url?.path ?? tab.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab.url?.path ?? "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { isHovered = $0 }
    }
}

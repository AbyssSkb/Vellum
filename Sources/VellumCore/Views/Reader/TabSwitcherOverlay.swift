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
    @State private var didEnter = false
    @State private var coordinates: NSView?
    @State private var flightImage: NSImage?
    @State private var flightRect = CGRect.zero
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
            ZStack(alignment: .topLeading) {
                TokyoNight.backgroundColor.opacity(isVisible ? 1 : 0)

                VStack(spacing: 22) {
                    searchHeader
                    tabList
                }
                .frame(width: layout.listWidth, height: layout.contentHeight)
                .position(x: layout.padding + layout.listWidth / 2, y: geometry.size.height / 2)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible || reduceMotion ? 0 : -8)

                if let tab = selectedTab {
                    paperStack(tab: tab, layout: layout)
                        .opacity(isVisible ? 1 : 0)
                    previewCaption(tab: tab)
                        .frame(width: layout.previewRegion.width, height: 52)
                        .position(x: layout.previewRegion.midX, y: layout.previewRegion.maxY + 34)
                        .opacity(isVisible ? 1 : 0)
                }

                if let flightImage {
                    paperImage(flightImage)
                        .frame(width: flightRect.width, height: flightRect.height)
                        .position(x: flightRect.midX, y: flightRect.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(TabSwitcherCoordinates { view in
                coordinates = view
                beginEntry(layout: layout)
            })
            .onAppear {
                selectedIndex = appState.tabs.firstIndex { $0.id == appState.selectedTabID } ?? 0
                updatePreviews(layout: layout)
                transitionTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled, !didEnter else { return }
                    didEnter = true
                    withAnimation(.easeOut(duration: 0.2)) { isVisible = true }
                }
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
                transitionTask?.cancel()
                flightImage = nil
                didEnter = true
                isVisible = true
                if isClosing { appState.hideTabSwitcher() }
                else { updatePreviews(layout: layout) }
            }
            .onChange(of: previews.images) { _, _ in beginEntry(layout: layout) }
        }
        .onDisappear {
            transitionTask?.cancel()
            previews.cancel()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(TokyoNight.blueColor)
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
                    .foregroundStyle(TokyoNight.mutedColor)
                    .frame(width: 32, height: 28)
                    .background(TokyoNight.panelColor, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(TokyoNight.borderColor, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(language.text(.cancel))
            .accessibilityLabel(language.text(.cancel))
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TokyoNight.blueColor.opacity(0.18)).frame(height: 1)
        }
    }

    private var tabList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if matches.isEmpty {
                        Text(language.text(.noMatchingTabs))
                            .font(.system(size: 13))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                            .padding(.horizontal, 16)
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

    private func paperStack(tab: PDFTab, layout: TabSwitcherLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([-1, 1], id: \.self) { offset in
                if matches.indices.contains(selectedIndex + offset) {
                    let neighbor = matches[selectedIndex + offset]
                    let rect = layout.paperRect(for: neighbor)
                    paper(tab: neighbor)
                        .frame(width: rect.width, height: rect.height)
                        .brightness(offset < 0 ? -0.22 : -0.12)
                        .rotationEffect(.degrees(Double(offset) * 5), anchor: .init(x: 0.5, y: 0.76))
                        .position(x: rect.midX + CGFloat(offset) * 22, y: rect.midY + 7)
                        .accessibilityHidden(true)
                }
            }
            let rect = layout.paperRect(for: tab)
            paper(tab: tab)
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .onTapGesture { dismiss(committing: tab) }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { dismiss(committing: tab) }
                .id(tab.id)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                .position(x: rect.midX, y: rect.midY)
                .opacity(flightImage == nil ? 1 : 0)
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.28), value: tab.id)
        .allowsHitTesting(!isClosing)
    }

    @ViewBuilder
    private func paper(tab: PDFTab) -> some View {
        if let image = previews.images[tab.id] {
            paperImage(image)
        } else {
            Rectangle().fill(TokyoNight.panelElevatedColor)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(TokyoNight.mutedColor.opacity(0.4))
                }
        }
    }

    private func paperImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }

    private func previewCaption(tab: PDFTab) -> some View {
        VStack(spacing: 7) {
            Text(tab.title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(TokyoNight.foregroundColor)
                .lineLimit(1)
            if let document = tab.document, document.pageCount > 0 {
                let index = min(max(tab.snapshot?.pageIndex ?? 0, 0), document.pageCount - 1)
                Text("\(index + 1) / \(document.pageCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(TokyoNight.mutedColor)
            }
        }
    }

    private func select(_ index: Int) {
        guard !isClosing else { return }
        didEnter = true
        transitionTask?.cancel()
        flightImage = nil
        withAnimation(.easeOut(duration: 0.2)) { isVisible = true }
        selectedIndex = min(max(index, 0), max(0, matches.count - 1))
    }

    private func updatePreviews(layout: TabSwitcherLayout) {
        var tabs = [PDFTab]()
        if let current = appState.selectedTab { tabs.append(current) }
        for index in [selectedIndex, selectedIndex - 1, selectedIndex + 1] where matches.indices.contains(index) {
            let tab = matches[index]
            if !tabs.contains(where: { $0.id == tab.id }) { tabs.append(tab) }
        }
        let scale = coordinates?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        // Match Retina paper size, with room for the expansion back into the reader.
        previews.update(tabs: tabs, maximumPixelSize: NSSize(
            width: max(layout.previewRegion.width, coordinates?.bounds.width ?? 0) * scale,
            height: max(layout.previewRegion.height, coordinates?.bounds.height ?? 0) * scale
        ))
    }

    private func readingRect(for tab: PDFTab) -> CGRect? {
        guard let coordinates, let reader = appState.activeReaderController as? VellumPDFView,
              reader.window === coordinates.window, reader.document === tab.document,
              let document = tab.document, document.pageCount > 0,
              let page = document.page(at: min(max(tab.snapshot?.pageIndex ?? 0, 0), document.pageCount - 1)),
              let rect = reader.viewRect(for: page.bounds(for: reader.displayBox), on: page) else { return nil }
        let converted = coordinates.convert(rect, from: reader)
        return converted.width > 0 && converted.height > 0 ? converted : nil
    }

    private func beginEntry(layout: TabSwitcherLayout) {
        guard !didEnter, !isClosing, let tab = selectedTab, tab.id == appState.selectedTabID,
              let image = previews.images[tab.id], let rect = readingRect(for: tab) else { return }
        didEnter = true
        transitionTask?.cancel()
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.32)) { isVisible = true }
        guard !reduceMotion else { return }
        flightImage = image
        flightRect = rect
        transitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.2, 0.75, 0.2, 1, duration: 0.58)) {
                flightRect = layout.paperRect(for: tab)
            }
            try? await Task.sleep(for: .milliseconds(580))
            guard !Task.isCancelled else { return }
            flightImage = nil
        }
    }

    private func dismiss(committing tab: PDFTab?) {
        guard !isClosing else { return }
        isClosing = true
        transitionTask?.cancel()
        let destination = tab ?? appState.selectedTab
        let source = selectedTab
        let layout = TabSwitcherLayout(size: coordinates?.bounds.size ?? .zero)
        let image = destination.flatMap { previews.images[$0.id] }
        let canMorph = !reduceMotion && destination?.id == source?.id && image != nil
        flightImage = canMorph ? image : nil
        if let source { flightRect = layout.paperRect(for: source) }
        if let tab { appState.selectTab(tab.id) }
        transitionTask = Task { @MainActor in
            // SwiftUI registers the newly active native PDFReader on the next layout pass.
            var target: CGRect?
            if let destination, canMorph {
                for _ in 0..<30 {
                    guard !Task.isCancelled else { return }
                    if let reader = appState.activeReaderController as? VellumPDFView,
                       reader.document === destination.document {
                        reader.layoutSubtreeIfNeeded()
                        reader.completePendingRestoreBeforeUserInteraction()
                        target = readingRect(for: destination)
                        if target != nil { break }
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.2, 0.75, 0.2, 1, duration: target == nil ? 0.2 : 0.5)) {
                isVisible = false
                if let target { flightRect = target }
                else { flightImage = nil }
            }
            try? await Task.sleep(for: .milliseconds(target == nil ? 200 : 500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.06)) { flightImage = nil }
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            appState.hideTabSwitcher()
        }
    }
}

private struct TabSwitcherLayout {
    let padding: CGFloat
    let listWidth: CGFloat
    let contentHeight: CGFloat
    let previewRegion: CGRect

    init(size: CGSize) {
        padding = min(max(size.width * 0.045, 26), 52)
        let width = max(0, size.width - padding * 2)
        listWidth = min(width * 0.39, 390)
        contentHeight = max(0, size.height - padding * 2)
        previewRegion = CGRect(x: padding + listWidth + 32, y: padding,
                               width: max(0, width - listWidth - 32), height: max(0, contentHeight - 72))
    }

    func paperRect(for tab: PDFTab) -> CGRect {
        let index = min(max(tab.snapshot?.pageIndex ?? 0, 0), max(0, (tab.document?.pageCount ?? 1) - 1))
        let size = tab.document?.page(at: index).map { PDFPageDisplayGeometry(page: $0, box: .cropBox).bounds.size }
            ?? CGSize(width: 612, height: 792)
        let scale = min(max(0, previewRegion.width - 48) / max(1, size.width),
                        max(0, previewRegion.height - 12) / max(1, size.height))
        return CGRect(x: previewRegion.midX - size.width * scale / 2,
                      y: previewRegion.midY - size.height * scale / 2,
                      width: size.width * scale, height: size.height * scale)
    }
}

private struct TabSwitcherCoordinates: NSViewRepresentable {
    let onReady: (NSView) -> Void
    func makeNSView(context: Context) -> CoordinateView {
        let view = CoordinateView()
        view.onReady = onReady
        return view
    }
    func updateNSView(_ nsView: CoordinateView, context: Context) { nsView.onReady = onReady }
    final class CoordinateView: NSView {
        var onReady: ((NSView) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onReady?(self)
            }
        }
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
        font = .systemFont(ofSize: 19, weight: .regular)
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
                .font: NSFont.systemFont(ofSize: 19, weight: .regular)
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
            VStack(alignment: .leading, spacing: 5) {
                Text(tab.title)
                    .font(.system(size: isSelected ? 17 : 13, weight: isSelected ? .medium : .regular))
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
        .padding(.horizontal, 16)
        .frame(height: 68)
        .background(isSelected ? TokyoNight.selectionColor.opacity(0.6)
                    : isHovered ? TokyoNight.panelElevatedColor.opacity(0.4) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(TokyoNight.blueColor).frame(width: 2, height: 19)
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

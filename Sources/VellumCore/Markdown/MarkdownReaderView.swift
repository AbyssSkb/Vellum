@preconcurrency import AppKit
import PDFKit
import SwiftUI
import WebKit

struct MarkdownReader: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
    let tabID: DocumentTab.ID
    let document: MarkdownDocument
    let snapshot: ReaderSnapshot?
    let isActive: Bool

    func makeNSView(context: Context) -> VellumMarkdownWebView {
        let view = VellumMarkdownWebView()
        view.appState = appState
        view.markdownDocument = document
        view.saveBeforeDismantle = { [weak appState, weak view] in
            guard let snapshot = view?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }
        view.load(document: document, restoring: snapshot)
        appState.setActiveReaderController(view, for: tabID)
        if isActive, !appState.isOutlineVisible {
            view.focus()
        }
        return view
    }

    func updateNSView(_ view: VellumMarkdownWebView, context: Context) {
        view.appState = appState
        view.saveBeforeDismantle = { [weak appState, weak view] in
            guard let snapshot = view?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }

        if view.markdownDocument != document {
            view.markdownDocument = document
            view.load(document: document, restoring: snapshot)
        }

        appState.setActiveReaderController(view, for: tabID)
        if isActive, !appState.isOutlineVisible {
            DispatchQueue.main.async { view.focus() }
        }
    }

    static func dismantleNSView(_ view: VellumMarkdownWebView, coordinator: ()) {
        view.saveBeforeDismantle?()
        view.cleanup()
    }
}

@MainActor
final class VellumMarkdownWebView: WKWebView, ReaderController {
    weak var appState: AppState?
    var markdownDocument: MarkdownDocument?
    var saveBeforeDismantle: (() -> Void)?

    private let aiInteraction = AIInteractionState()
    private var searchOverlay: MarkdownSearchOverlayView?
    private var searchQuery = ""
    private var searchCount = 0
    private var searchIndex = 0
    private var pendingRestoreSnapshot: ReaderSnapshot?
    private var currentSnapshot = ReaderSnapshot(
        pageIndex: 0,
        pointOnPage: .zero,
        scrollOrigin: .zero,
        scaleFactor: 1,
        autoScales: false
    )
    private var renderDirectoryURL: URL?
    private var jumpBackStack: [ReaderSnapshot] = []
    private var jumpForwardStack: [ReaderSnapshot] = []

    init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(macOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        super.init(frame: .zero, configuration: configuration)
        controller.add(self, name: "vellumSnapshotChanged")
        navigationDelegate = self
        allowsBackForwardNavigationGestures = false
        setValue(false, forKey: "drawsBackground")
        wantsLayer = true
        layer?.backgroundColor = TokyoNight.background.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    var isAIInteractionActive: Bool {
        aiInteraction.isActive
    }

    var hasNavigableTextSelection: Bool {
        false
    }

    var hasSearchTextTarget: Bool {
        searchCount > 0
    }

    var isPageOverviewActive: Bool {
        false
    }

    var documentKey: String? {
        markdownDocument?.url.standardizedFileURL.path
    }

    func load(document: MarkdownDocument, restoring snapshot: ReaderSnapshot?) {
        pendingRestoreSnapshot = snapshot
        let html = MarkdownHTMLRenderer.html(for: document)
        do {
            let htmlURL = try writeRenderHTML(html)
            let readAccessURL = readAccessRoot(for: document.url, htmlURL: htmlURL)
            loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
        } catch {
            loadHTMLString(html, baseURL: document.url.deletingLastPathComponent())
        }
    }

    func cleanup() {
        aiInteraction.clearActiveRequest()
        aiInteraction.clearPopoverState()
        configuration.userContentController.removeScriptMessageHandler(forName: "vellumSnapshotChanged")
        removeRenderDirectory()
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    func snapshot() -> ReaderSnapshot? {
        currentSnapshot
    }

    func beginPageOverview() -> Bool { false }
    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool { false }
    func finishPageOverview() {}

    func beginSearchCommand() {
        let overlay = MarkdownSearchOverlayView(query: searchQuery)
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.onQueryChanged = { [weak self] query in
            self?.updateSearch(query: query)
        }
        overlay.onCommit = { [weak self] in
            self?.commitSearch()
        }
        overlay.onCancel = { [weak self] in
            _ = self?.dismissSearchOverlay(clear: false)
        }
        searchOverlay?.removeFromSuperview()
        addSubview(overlay)
        searchOverlay = overlay
        overlay.update(status: searchStatus())
        overlay.focus()
    }

    func handleAIKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              aiInteraction.activeExplanationModel != nil || aiInteraction.activeConversationModel != nil,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "\u{1b}":
            dismissActiveAIInteraction(clearSelection: true)
            return true
        case "j":
            aiInteraction.activeWebView?.pulseScroll(direction: 1)
            return true
        case "k":
            aiInteraction.activeWebView?.pulseScroll(direction: -1)
            return true
        default:
            return false
        }
    }

    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers else { return false }
        return handleTextSelectionKey(key, eventType: event.type)
    }

    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool {
        guard rawKey == "\u{1b}", eventType == .keyDown else { return false }
        if dismissSearchOverlay(clear: true) {
            return true
        }
        evaluate("window.vellumClearSelection && window.vellumClearSelection();")
        return false
    }

    func vimDeleteHighlightsForSelection() -> Bool { false }

    func vimScroll(x: CGFloat, y: CGFloat) {
        evaluate("window.vellumScrollBy(\(Double(x)), \(Double(-y)));")
    }

    func vimMoveByPage(_ delta: Int) {
        evaluate("window.vellumPageBy(\(delta));")
    }

    func vimGoToFirstPage() {
        recordJumpSource()
        evaluate("window.vellumFirst();")
    }

    func vimGoToLastPage() {
        recordJumpSource()
        evaluate("window.vellumLast();")
    }

    func vimGoToPage(_ pageNumber: Int) {
        vimGoToMarkdownLine(pageNumber)
    }

    func vimGoToMarkdownLine(_ lineNumber: Int) {
        recordJumpSource()
        evaluate("window.vellumJumpToLine(\(lineNumber));")
    }

    func vimGoToDestination(_ destination: PDFDestination) {}

    func vimJumpBack() {
        guard let previous = jumpBackStack.popLast() else { return }
        jumpForwardStack.append(currentSnapshot)
        restore(previous)
    }

    func vimJumpForward() {
        guard let next = jumpForwardStack.popLast() else { return }
        jumpBackStack.append(currentSnapshot)
        restore(next)
    }

    func vimSearchNext() {
        if searchCount == 0, !searchQuery.isEmpty {
            updateSearch(query: searchQuery)
            return
        }
        moveSearch(delta: 1)
    }

    func vimSearchPrevious() {
        if searchCount == 0, !searchQuery.isEmpty {
            updateSearch(query: searchQuery)
            return
        }
        moveSearch(delta: -1)
    }

    func vimMaterializeSearchSelection() {
        evaluate("window.vellumMaterializeSearchSelection();") { [weak self] result in
            let text = result as? String
            if text?.nilIfEmpty == nil {
                NSSound.beep()
            }
            self?.focus()
        }
    }

    func vimCopySelection() {
        selectedText { text in
            guard let text = text?.nilIfEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func vimHighlightSelection(color: NSColor) {
        showAINotification(AppUILanguage.saved().text(.markdownHighlightUnavailable))
    }

    func vimExplainSelectedHighlight() {
        aiContextForSelection { [weak self] context in
            guard let self else { return }
            guard let context else {
                self.showAINotification(AIExplanationError.noSelection.localizedDescription)
                NSSound.beep()
                return
            }
            self.streamExplanation(context: context)
        }
    }

    func vimStartAIConversation() {
        aiContextForSelection { [weak self] context in
            guard let self else { return }
            guard let context else {
                self.showAINotification(AIExplanationError.noSelection.localizedDescription)
                NSSound.beep()
                return
            }
            let model = AIConversationPopoverModel(context: context)
            self.showAIConversationPopover(model: model)
        }
    }

    func showAINotification(_ message: String) {
        showAIToast(message)
    }

    func restoreAIExplanation(_ item: AIExplanationHistoryItem) {
        let model = AIExplanationPopoverModel(
            title: item.selectedText.aiPopoverTitle,
            text: item.explanation,
            initialHeight: AIExplanationPopoverMetrics.estimatedHeight(for: item.explanation),
            pronunciationSpeechText: item.selectedText
        )
        showAIExplanationOverlay(model: model, kind: .message)
    }

    func restoreAIConversation(_ item: AIConversationHistoryItem) {
        let model = AIConversationPopoverModel(context: item.context, historyID: item.id)
        model.messages = item.messages
        model.refreshPreferredHeight()
        showAIConversationPopover(model: model)
    }

    func vimZoom(by factor: CGFloat) {
        evaluate("window.vellumZoomBy(\(Double(factor)));")
    }

    func vimZoomToPageFit() {
        evaluate("window.vellumSetFontScale(1);")
    }

    func vimZoomToFit() {
        evaluate("window.vellumSetFontScale(1.14);")
    }

    func restore(_ snapshot: ReaderSnapshot?) {
        guard let snapshot else { return }
        currentSnapshot = snapshot
        let y = snapshot.scrollOrigin?.y ?? 0
        let line = max(1, snapshot.pageIndex + 1)
        let scale = snapshot.scaleFactor > 0 ? snapshot.scaleFactor : 1
        evaluate("window.vellumRestore({ y: \(Double(y)), line: \(line), fontScale: \(Double(scale)) });")
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

    private func evaluate(_ script: String, completion: ((Any?) -> Void)? = nil) {
        evaluateJavaScript(script) { result, _ in
            Task { @MainActor in completion?(result) }
        }
    }

    private func updateSearch(query: String) {
        searchQuery = query
        let encoded = jsonString(query)
        evaluate("window.vellumSearch(\(encoded));") { [weak self] result in
            self?.applySearchResult(result)
        }
    }

    private func commitSearch() {
        guard searchCount > 0 else {
            searchOverlay?.update(status: searchStatus())
            return
        }
        searchOverlay?.showMini(query: searchQuery)
        focus()
    }

    @discardableResult
    private func dismissSearchOverlay(clear: Bool) -> Bool {
        let hadOverlay = searchOverlay != nil
        searchOverlay?.removeFromSuperview()
        searchOverlay = nil
        if clear {
            searchCount = 0
            searchIndex = 0
            searchQuery = ""
            evaluate("window.vellumClearSearch && window.vellumClearSearch();")
        }
        if hadOverlay {
            focus()
        }
        return hadOverlay
    }

    private func moveSearch(delta: Int) {
        evaluate("window.vellumSearchMove(\(delta));") { [weak self] result in
            self?.applySearchResult(result)
        }
    }

    private func applySearchResult(_ result: Any?) {
        guard let dictionary = result as? [String: Any] else { return }
        searchCount = dictionary["count"] as? Int ?? 0
        searchIndex = dictionary["active"] as? Int ?? 0
        searchOverlay?.update(status: searchStatus())
    }

    private func searchStatus() -> MarkdownSearchOverlayView.Status {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .hint(AppUILanguage.saved().text(.searchTypeHint))
        }
        if searchCount == 0 {
            return .error(AppUILanguage.saved().text(.searchNoMatch))
        }
        return .count(current: searchIndex, total: searchCount)
    }

    private func selectedText(_ completion: @escaping (String?) -> Void) {
        evaluate("window.vellumSelectedText && window.vellumSelectedText();") { result in
            completion(result as? String)
        }
    }

    private func aiContextForSelection(_ completion: @escaping (AIExplanationContext?) -> Void) {
        guard let markdownDocument else {
            completion(nil)
            return
        }
        evaluate("window.vellumContext && window.vellumContext();") { result in
            guard let dictionary = result as? [String: Any],
                  let selectedText = (dictionary["selectedText"] as? String)?.nilIfEmpty else {
                completion(nil)
                return
            }
            let line = dictionary["line"] as? Int ?? 1
            let normalized = AISelectedTextNormalizer.normalized(selectedText)
            guard !normalized.isEmpty else {
                completion(nil)
                return
            }
            completion(
                AIExplanationContext(
                    selectedText: normalized,
                    previousParagraph: nil,
                    currentParagraph: dictionary["currentParagraph"] as? String,
                    nextParagraph: nil,
                    nearbyText: (dictionary["nearbyText"] as? String)?.limitedForAIContext(5000) ?? normalized,
                    fileName: markdownDocument.url.lastPathComponent,
                    documentKey: markdownDocument.url.standardizedFileURL.path,
                    directoryName: markdownDocument.url.deletingLastPathComponent().lastPathComponent,
                    outlineTitle: (dictionary["outlineTitle"] as? String)?.nilIfEmpty,
                    pageNumbers: [line],
                    anchoredContext: "Line \(line):\n\((dictionary["nearbyText"] as? String)?.limitedForAIContext(5000) ?? normalized)"
                )
            )
        }
    }

    private func streamExplanation(context: AIExplanationContext) {
        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current()
        } catch {
            showAINotification(error.localizedDescription)
            NSSound.beep()
            return
        }

        aiInteraction.explanationTask?.cancel()
        let model = AIExplanationPopoverModel(
            title: context.selectedText.aiPopoverTitle,
            isStreaming: true,
            initialHeight: AIExplanationPopoverMetrics.streamingMinimumHeight,
            pronunciationSpeechText: context.selectedText
        )
        showAIExplanationOverlay(model: model, kind: .streaming)

        let task = Task { @MainActor [weak self, model] in
            do {
                let explanation = try await AIExplanationClient.streamExplanation(
                    context: context,
                    configuration: configuration,
                    onChunk: { chunk in model.append(chunk) }
                )
                self?.appState?.upsertAIExplanationHistory(
                    AIExplanationHistoryItem(
                        id: UUID(),
                        selectedText: context.selectedText,
                        explanation: explanation,
                        fileName: context.fileName,
                        documentKey: context.documentKey,
                        pageNumbers: context.pageNumbers,
                        updatedAt: Date()
                    )
                )
                model.isStreaming = false
                model.requestStatus = .completed
                self?.aiInteraction.explanationTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                model.isStreaming = false
                model.requestStatus = .failed
                model.title = "AI request failed"
                model.text = error.localizedDescription
                self?.aiInteraction.explanationTask = nil
                NSSound.beep()
            }
        }
        aiInteraction.explanationTask = task
    }

    private func showAIConversationPopover(model: AIConversationPopoverModel) {
        hideAIExplanationPopover()
        let overlay = showAIFloatingOverlay(
            rootView: AIConversationPopoverView(
                model: model,
                onDismiss: { [weak self] in self?.dismissActiveAIInteraction(clearSelection: true) },
                onSend: { [weak self, weak model] prompt in self?.sendAIConversationMessage(prompt, model: model) },
                onPreferredSizeChange: { [weak self] size in self?.resizeAIFloatingOverlay(size: size) }
            ),
            size: model.preferredSize
        )
        aiInteraction.conversationOverlay = overlay
        aiInteraction.activeConversationModel = model
    }

    private func sendAIConversationMessage(_ prompt: String, model: AIConversationPopoverModel?) {
        guard let model, aiInteraction.activeConversationModel === model, !model.isSending else { return }
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current(profile: .conversation)
        } catch {
            model.errorMessage = error.localizedDescription
            model.requestStatus = .failed
            NSSound.beep()
            return
        }

        model.errorMessage = nil
        model.isSending = true
        model.requestStatus = .streaming
        model.messages.append(AIConversationMessage(role: .user, content: question))
        model.messages.append(AIConversationMessage(role: .assistant, content: ""))
        model.refreshPreferredHeight()
        appState?.upsertAIConversationHistory(model.historyItem)
        let messagesForRequest = Array(model.messages.dropLast())
        let context = model.context

        aiInteraction.conversationTask?.cancel()
        let task = Task { @MainActor [weak self, weak model] in
            do {
                let answer = try await AIExplanationClient.streamConversation(
                    context: context,
                    messages: messagesForRequest,
                    configuration: configuration,
                    onChunk: { chunk in
                        model?.appendToLatestAssistant(chunk)
                        if let model {
                            self?.appState?.upsertAIConversationHistory(model.historyItem)
                        }
                    }
                )
                guard let model else { return }
                model.replaceLatestAssistant(with: answer)
                model.isSending = false
                model.requestStatus = .completed
                self?.appState?.upsertAIConversationHistory(model.historyItem)
                self?.aiInteraction.conversationTask = nil
            } catch {
                guard !Task.isCancelled, let model else { return }
                model.errorMessage = error.localizedDescription
                model.isSending = false
                model.requestStatus = .failed
                model.refreshPreferredHeight()
                self?.appState?.upsertAIConversationHistory(model.historyItem)
                self?.aiInteraction.conversationTask = nil
                NSSound.beep()
            }
        }
        aiInteraction.conversationTask = task
    }

    private func showAIExplanationOverlay(model: AIExplanationPopoverModel, kind: AIExplanationPopoverKind) {
        hideAIExplanationPopover()
        let overlay = showAIFloatingOverlay(
            rootView: AIExplanationPopoverView(
                model: model,
                kind: kind,
                onDismiss: { [weak self] in self?.dismissActiveAIInteraction(clearSelection: true) },
                onHighlight: {},
                onCycleColor: {},
                onContentHeightChange: { [weak self, model, kind] height in
                    guard kind.allowsDynamicHeight else { return }
                    if model.updateContentHeight(height, minimumHeight: AIExplanationPopoverMetrics.streamingMinimumHeight) {
                        self?.resizeAIFloatingOverlay(size: model.preferredSize)
                    }
                },
                onWebViewReady: { [weak self, kind] webView in
                    self?.aiInteraction.activeWebView = webView
                    guard kind.shouldFocusWebView else { return }
                    DispatchQueue.main.async { [weak webView] in
                        webView?.window?.makeFirstResponder(webView)
                    }
                }
            ),
            size: model.preferredSize
        )
        aiInteraction.explanationOverlay = overlay
        aiInteraction.activeExplanationModel = model
    }

    private func showAIFloatingOverlay<Content: View>(rootView: Content, size: NSSize) -> NSView {
        let hostingView = NSHostingView(rootView: rootView)
        let overlay = MarkdownAIFloatingOverlayContainerView(contentView: hostingView)
        overlay.frame = floatingOverlayFrame(size: size)
        overlay.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(overlay)
        return overlay
    }

    private func resizeAIFloatingOverlay(size: NSSize) {
        let overlay = aiInteraction.explanationOverlay ?? aiInteraction.conversationOverlay
        overlay?.frame = floatingOverlayFrame(size: size)
    }

    private func floatingOverlayFrame(size: NSSize) -> NSRect {
        NSRect(
            x: max(18, bounds.midX - size.width / 2),
            y: max(18, bounds.maxY - size.height - 76),
            width: min(size.width, bounds.width - 36),
            height: min(size.height, bounds.height - 36)
        )
    }

    private func showAIToast(_ message: String) {
        aiInteraction.toastHideWorkItem?.cancel()
        aiInteraction.toastView?.removeFromSuperview()
        let toast = MarkdownAIToastView(message: message)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alphaValue = 0
        addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18)
        ])
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            toast.animator().alphaValue = 1
        }
        let workItem = DispatchWorkItem { [weak toast] in toast?.removeFromSuperview() }
        aiInteraction.toastView = toast
        aiInteraction.toastHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    private func hideAIExplanationPopover() {
        aiInteraction.clearPopoverState()
    }

    private func dismissActiveAIInteraction(clearSelection: Bool) {
        aiInteraction.clearActiveRequest()
        hideAIExplanationPopover()
        if clearSelection {
            evaluate("window.vellumClearSelection && window.vellumClearSelection();")
        }
        focus()
    }

    private func recordJumpSource() {
        if jumpBackStack.last != currentSnapshot {
            jumpBackStack.append(currentSnapshot)
        }
        jumpForwardStack.removeAll()
        if jumpBackStack.count > 100 {
            jumpBackStack.removeFirst(jumpBackStack.count - 100)
        }
    }

    private func jsonString(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }

    private func writeRenderHTML(_ html: String) throws -> URL {
        removeRenderDirectory()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumMarkdown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let htmlURL = directory.appendingPathComponent("index.html")
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        renderDirectoryURL = directory
        return htmlURL
    }

    private func removeRenderDirectory() {
        guard let renderDirectoryURL else { return }
        try? FileManager.default.removeItem(at: renderDirectoryURL)
        self.renderDirectoryURL = nil
    }

    private func readAccessRoot(for documentURL: URL, htmlURL: URL) -> URL {
        let candidates = [
            documentURL.deletingLastPathComponent(),
            htmlURL.deletingLastPathComponent(),
            MarkdownRendererResources.bundleURL
        ].compactMap { $0 }
        let components = candidates.map { $0.standardizedFileURL.pathComponents }
        guard var common = components.first else {
            return URL(fileURLWithPath: "/")
        }
        for pathComponents in components.dropFirst() {
            while !pathComponents.starts(with: common), !common.isEmpty {
                common.removeLast()
            }
        }
        let path = common.isEmpty ? "/" : NSString.path(withComponents: common)
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

extension VellumMarkdownWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restore(pendingRestoreSnapshot)
        pendingRestoreSnapshot = nil
    }
}

extension VellumMarkdownWebView: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vellumSnapshotChanged" else { return }
        let body = message.body
        guard let dictionary = body as? [String: Any] else { return }
        let y = dictionary["y"] as? CGFloat ?? 0
        let line = max(1, dictionary["line"] as? Int ?? 1)
        let fontScale = dictionary["fontScale"] as? CGFloat ?? 1
        currentSnapshot = ReaderSnapshot(
            pageIndex: line - 1,
            pointOnPage: .zero,
            scrollOrigin: NSPoint(x: 0, y: y),
            scaleFactor: fontScale,
            autoScales: false
        )
        guard let selectedTabID = appState?.selectedTabID else { return }
        appState?.saveSnapshot(currentSnapshot, for: selectedTabID)
    }
}

private final class MarkdownAIFloatingOverlayContainerView: NSView {
    private let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 22
        layer?.shadowOffset = NSSize(width: 0, height: -8)
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)
    }

    override var acceptsFirstResponder: Bool { true }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        contentView.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
    }
}

private final class MarkdownAIToastView: NSView {
    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = TokyoNight.panelElevated.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = TokyoNight.border.withAlphaComponent(0.85).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = TokyoNight.cyan
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = TokyoNight.foreground
        label.backgroundColor = .clear
        label.isBezeled = false
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class MarkdownSearchOverlayView: NSView, NSTextFieldDelegate {
    enum Status {
        case hint(String)
        case error(String)
        case count(current: Int, total: Int)

        var text: String {
            switch self {
            case .hint(let text), .error(let text): return text
            case .count(let current, let total): return "\(current)/\(total)"
            }
        }

        var color: NSColor {
            switch self {
            case .hint: return TokyoNight.muted
            case .error: return TokyoNight.red
            case .count: return TokyoNight.cyan
            }
        }
    }

    var onQueryChanged: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    private let container = NSVisualEffectView()
    private let textField = MarkdownSearchTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var isMini = false

    init(query: String) {
        super.init(frame: .zero)
        configure()
        textField.stringValue = query
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = isMini ? min(max(measuredWidth(textField.stringValue) + 88, 128), 360) : min(max(bounds.width * 0.46, 460), bounds.width - 40, 720)
        container.frame = NSRect(x: bounds.midX - width / 2, y: 24, width: width, height: isMini ? 34 : 44)
        textField.frame = NSRect(x: 16, y: container.bounds.midY - 13, width: max(80, container.bounds.width - 104), height: 26)
        statusLabel.frame = NSRect(x: container.bounds.maxX - 82, y: 0, width: 66, height: container.bounds.height)
    }

    func focus() {
        window?.makeFirstResponder(textField)
        textField.currentEditor()?.moveToEndOfLine(self)
    }

    func update(status: Status) {
        statusLabel.stringValue = status.text
        statusLabel.textColor = status.color
    }

    func showMini(query: String) {
        isMini = true
        textField.stringValue = query
        textField.isEditable = false
        needsLayout = true
    }

    func controlTextDidChange(_ obj: Notification) {
        onQueryChanged?(textField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
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

    private func configure() {
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = TokyoNight.border.withAlphaComponent(0.72).cgColor
        textField.delegate = self
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 15)
        textField.textColor = TokyoNight.foreground
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = TokyoNight.muted
        statusLabel.alignment = .center
        addSubview(container)
        container.addSubview(textField)
        container.addSubview(statusLabel)
    }

    private func measuredWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: textField.font ?? .systemFont(ofSize: 13)]).width)
    }
}

private final class MarkdownSearchTextField: NSTextField {
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            if let delegate,
               delegate.control?(
                self,
                textView: currentEditor() as? NSTextView ?? NSTextView(),
                doCommandBy: #selector(NSResponder.insertNewline(_:))
               ) == true {
                return
            }
        case 53:
            if let delegate,
               delegate.control?(
                self,
                textView: currentEditor() as? NSTextView ?? NSTextView(),
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
               ) == true {
                return
            }
        default:
            break
        }
        super.keyDown(with: event)
    }
}

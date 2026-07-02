@preconcurrency import AppKit
import PDFKit
import SwiftUI


enum PendingRestoreAction {
    case initial(generation: Int)
    case snapshot(snapshot: ReaderSnapshot, page: PDFPage, generation: Int)

    var generation: Int {
        switch self {
        case .initial(let generation),
             .snapshot(_, _, let generation):
            return generation
        }
    }
}

final class VellumPDFView: PDFView {
    static let textSelectionNavigationKeys: Set<String> = ["h", "j", "k", "l", "w", "b", "e"]

    weak var appState: AppState?
    var saveBeforeDismantle: (() -> Void)?
    let animationState = ReaderAnimationState()
    var jumpBackStack: [ReaderSnapshot] = []
    var jumpForwardStack: [ReaderSnapshot] = []
    var restoreGeneration = 0
    var pendingActivationSnapshot: ReaderSnapshot?
    var explanationTrackingArea: NSTrackingArea?
    let aiInteraction = AIInteractionState()
    var isMouseSelectingText = false
    nonisolated(unsafe) var mouseSelectionScrollWheelMonitor: Any?
    var scrollBoundsObserver: NSObjectProtocol?
    weak var observedScrollClipView: NSClipView?
    var readerStateSaveWorkItem: DispatchWorkItem?
    var lastMouseSelectionMouseUpTimestamp: TimeInterval?
    var pendingDoubleClickTextSelectionPoint: NSPoint?
    var pendingClickHorizontalOrigin: CGFloat?
    var didHandleDoubleClickTextSelectionMouseDown = false
    var didDragDuringCurrentMouseSequence = false
    var didCompleteInitialPointerInteraction = false
    var pendingRestoreAction: PendingRestoreAction?
    var textSelectionNavigationState: VimTextSelectionNavigationState?
    var pageOverviewController: PageOverviewController?
    var searchController: PDFSearchController?

    override var acceptsFirstResponder: Bool { true }

    deinit {
        if let mouseSelectionScrollWheelMonitor {
            NSEvent.removeMonitor(mouseSelectionScrollWheelMonitor)
        }
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        readerStateSaveWorkItem?.cancel()
    }

    var isAIInteractionActive: Bool {
        aiInteraction.isActive
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

    var hasSearchTextTarget: Bool {
        searchController?.hasTextTarget == true
    }

    var hasAnyTextSelection: Bool {
        currentSelection != nil
    }

    var isPageOverviewActive: Bool {
        pageOverviewController != nil
    }

    var documentKey: String? {
        document?.documentURL?.standardizedFileURL.path
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
            let canHandleSearchEscape = searchController?.canHandleEscape == true
            guard hasAnyTextSelection || canHandleSearchEscape else { return false }
            if eventType == .keyDown {
                if hasAnyTextSelection {
                    clearTextSelectionForVimNavigation()
                } else if searchController?.handleEscape() == true {
                    focus()
                }
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

    func clearTextSelectionForVimNavigation() {
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
        configureMouseSelectionScrollWheelMonitor()
        updateExplanationTrackingArea()
        didDragDuringCurrentMouseSequence = false
        pendingClickHorizontalOrigin = nil
        pendingDoubleClickTextSelectionPoint = nil
        lastMouseSelectionMouseUpTimestamp = nil
        didHandleDoubleClickTextSelectionMouseDown = false
        didCompleteInitialPointerInteraction = false
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

    func vimCopySelection() {
        if let selection = currentSelection,
           let selectedText = selection.string?.nilIfEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
            clearTextSelectionForVimNavigation()
            return
        }

        guard let selectedText = searchController?.activeSearchSelection?.string?.nilIfEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
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
        completePendingRestoreBeforeUserInteraction()
        isMouseSelectingText = true
        lastMouseSelectionMouseUpTimestamp = nil
        pendingDoubleClickTextSelectionPoint = doubleClickTextSelectionPoint(for: event)
        pendingClickHorizontalOrigin = clickHorizontalOriginToPreserve(for: event)
        didHandleDoubleClickTextSelectionMouseDown = false
        didDragDuringCurrentMouseSequence = false
        searchController?.markReaderNavigated()
        textSelectionNavigationState = nil
        hideAIExplanationPopover()
        if recordJumpSourceIfNeededForLinkClick(with: event) {
            cancelPendingRestore()
        }
        if handleDoubleClickTextSelectionMouseDown(with: event) {
            return
        }
        if pendingClickHorizontalOrigin != nil {
            window?.disableScreenUpdatesUntilFlush()
        }
        super.mouseDown(with: event)
        restoreHorizontalOrigin(pendingClickHorizontalOrigin)
    }

    override func mouseDragged(with event: NSEvent) {
        isMouseSelectingText = true
        pendingDoubleClickTextSelectionPoint = nil
        didHandleDoubleClickTextSelectionMouseDown = false
        didDragDuringCurrentMouseSequence = true
        pendingClickHorizontalOrigin = nil
        cancelPendingRestore()
        searchController?.markReaderNavigated()
        hideAIExplanationPopover()
        super.mouseDragged(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()

        if explainSelectedTextIfNeededForMiddleClick(with: event) {
            return
        }

        super.otherMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let pointInView = convert(event.locationInWindow, from: nil)
        let menu = super.menu(for: event) ?? NSMenu()

        guard let selection = currentSelection,
              selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              selectionCovers(pointInView, selection: selection) else {
            return menu
        }

        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }

        let language = AppUILanguage.saved()
        let chatItem = NSMenuItem(
            title: language.text(.aiConversation),
            action: #selector(openAIConversationFromContextMenu),
            keyEquivalent: "i"
        )
        chatItem.target = self
        chatItem.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil)
        menu.addItem(chatItem)

        return menu
    }

    override func scrollWheel(with event: NSEvent) {
        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        searchController?.markReaderNavigated()

        if isMouseSelectingText || (NSEvent.pressedMouseButtons & 1) == 1 {
            if scrollPDFViewDuringMouseSelection(with: event) {
                return
            }
        }

        super.scrollWheel(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        lastMouseSelectionMouseUpTimestamp = event.timestamp
        let didHandleDoubleClickTextSelectionMouseDown = didHandleDoubleClickTextSelectionMouseDown
        self.didHandleDoubleClickTextSelectionMouseDown = false
        if !didHandleDoubleClickTextSelectionMouseDown {
            super.mouseUp(with: event)
        }
        let doubleClickPoint = pendingDoubleClickTextSelectionPoint
        let clickHorizontalOrigin = pendingClickHorizontalOrigin
        let isInitialPointerInteraction = !didCompleteInitialPointerInteraction
        pendingDoubleClickTextSelectionPoint = nil
        pendingClickHorizontalOrigin = nil
        let shouldClearTransientSelection = !didDragDuringCurrentMouseSequence
            && doubleClickPoint == nil
            && isInitialPointerInteraction
            && currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).count == 1
        let shouldRestoreHorizontalOrigin = !didDragDuringCurrentMouseSequence
        didDragDuringCurrentMouseSequence = false
        didCompleteInitialPointerInteraction = true
        if shouldRestoreHorizontalOrigin {
            DispatchQueue.main.async { [weak self] in
                self?.restoreHorizontalOrigin(clickHorizontalOrigin)
                if shouldClearTransientSelection {
                    self?.clearSelection()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.isMouseSelectingText = false
            self.lastMouseSelectionMouseUpTimestamp = nil
            self.explainDoubleClickedTextIfNeeded(at: doubleClickPoint)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if aiInteraction.hoveredAnnotation != nil {
            scheduleHoverPopoverHide()
        }
    }

    func updateExplanationTrackingArea() {
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

    func configurePDFScrollers() {
        guard let scrollView = pdfScrollView else { return }
        PDFOverlayScrollerStyleLock.install(on: scrollView)
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .default
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        configureReaderStatePersistence(for: scrollView)
    }

    private func configureReaderStatePersistence(for scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        guard observedScrollClipView !== clipView else { return }

        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }

        observedScrollClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleReaderStateSave()
            }
        }
    }

    func scheduleReaderStateSave(delay: TimeInterval = 0.35) {
        guard window != nil else { return }
        readerStateSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.appState?.saveActiveReaderState()
            }
        }
        readerStateSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func configureMouseSelectionScrollWheelMonitor() {
        if window == nil {
            removeMouseSelectionScrollWheelMonitor()
        } else if mouseSelectionScrollWheelMonitor == nil {
            mouseSelectionScrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleMouseSelectionScrollWheel(event) ?? event
            }
        }
    }

    private func removeMouseSelectionScrollWheelMonitor() {
        if let mouseSelectionScrollWheelMonitor {
            NSEvent.removeMonitor(mouseSelectionScrollWheelMonitor)
            self.mouseSelectionScrollWheelMonitor = nil
        }
    }

    private func handleMouseSelectionScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard isMouseSelectingText || currentSelection != nil || lastMouseSelectionMouseUpTimestamp != nil,
              event.window === window else {
            return event
        }

        let isLeftMouseDown = (NSEvent.pressedMouseButtons & 1) == 1
        if isLeftMouseDown || isMouseSelectingText {
            completePendingRestoreBeforeUserInteraction()
            cancelPendingRestore()
            searchController?.markReaderNavigated()
            scrollPDFViewDuringMouseSelection(with: event)
            return nil
        }

        if let lastMouseSelectionMouseUpTimestamp,
           event.timestamp <= lastMouseSelectionMouseUpTimestamp {
            return nil
        }

        return event
    }

    @discardableResult
    private func scrollPDFViewDuringMouseSelection(with event: NSEvent) -> Bool {
        guard let scrollView = pdfScrollView else { return false }

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        guard documentSize.height > clipView.bounds.height || documentSize.width > clipView.bounds.width else {
            return false
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let deltaX = event.scrollingDeltaX * multiplier
        let deltaY = event.scrollingDeltaY * multiplier
        let maximumX = max(0, documentSize.width - clipView.bounds.width)
        let maximumY = max(0, documentSize.height - clipView.bounds.height)
        let current = clipView.bounds.origin
        let proposed = NSPoint(
            x: min(max(0, current.x + deltaX), maximumX),
            y: min(max(0, current.y - deltaY), maximumY)
        )

        guard proposed != current else { return false }
        clipView.scroll(to: proposed)
        scrollView.reflectScrolledClipView(clipView)
        scheduleReaderStateSave()
        return true
    }

    private func doubleClickTextSelectionPoint(for event: NSEvent) -> NSPoint? {
        guard event.clickCount == 2,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }

        return convert(event.locationInWindow, from: nil)
    }

    private func clickHorizontalOriginToPreserve(for event: NSEvent) -> CGFloat? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }
        guard event.clickCount == 2 || !didCompleteInitialPointerInteraction else { return nil }

        let pointInView = convert(event.locationInWindow, from: nil)
        guard linkAnnotation(at: pointInView) == nil else { return nil }

        return currentHorizontalOrigin()
    }

    private func handleDoubleClickTextSelectionMouseDown(with event: NSEvent) -> Bool {
        guard let pointInView = pendingDoubleClickTextSelectionPoint,
              event.clickCount == 2,
              linkAnnotation(at: pointInView) == nil,
              let page = page(for: pointInView, nearest: false) else {
            return false
        }

        let pointOnPage = convert(pointInView, to: page)
        guard let selection = page.selectionForWord(at: pointOnPage),
              selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }

        cancelPendingRestore()
        didHandleDoubleClickTextSelectionMouseDown = true
        setCurrentSelection(selection, animate: false)
        needsDisplay = true
        restoreHorizontalOrigin(pendingClickHorizontalOrigin)
        return true
    }

    @discardableResult
    private func recordJumpSourceIfNeededForLinkClick(with event: NSEvent) -> Bool {
        guard event.clickCount == 1 else { return false }

        let pointInView = convert(event.locationInWindow, from: nil)
        guard PDFLinkNavigation.shouldRecordJumpSource(for: linkAnnotation(at: pointInView)) else { return false }

        recordJumpSource()
        return true
    }

    private func linkAnnotation(at pointInView: NSPoint) -> PDFAnnotation? {
        guard let page = page(for: pointInView, nearest: false) else { return nil }

        let pointOnPage = convert(pointInView, to: page)
        let annotation = page.annotation(at: pointOnPage)
        return annotation?.type == "Link" ? annotation : nil
    }

    private func explainDoubleClickedTextIfNeeded(at point: NSPoint?) {
        guard let point,
              AppPreferences.doubleClickTranslatesSelection(),
              aiInteraction.isActive == false,
              let selection = currentSelection,
              selectionCovers(point, selection: selection),
              selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        vimExplainSelectedHighlight()
    }

    private func explainSelectedTextIfNeededForMiddleClick(with event: NSEvent) -> Bool {
        let pointInView = convert(event.locationInWindow, from: nil)
        let selection = currentSelection
        let selectedText = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard AIExplanationMouseTrigger.shouldExplainSelection(
            eventType: event.type,
            buttonNumber: event.buttonNumber,
            clickCount: event.clickCount,
            modifierFlags: event.modifierFlags,
            isAIInteractionActive: aiInteraction.isActive,
            hasSelectedText: selectedText?.isEmpty == false,
            pointIsInsideSelection: selection.map { selectionCovers(pointInView, selection: $0) } ?? false
        ) else {
            return false
        }

        focus()
        vimExplainSelectedHighlight()
        return true
    }

    @objc private func openAIConversationFromContextMenu() {
        focus()
        vimStartAIConversation()
    }

    private func selectionCovers(_ pointInView: NSPoint, selection: PDFSelection) -> Bool {
        guard let page = page(for: pointInView, nearest: false),
              selection.pages.contains(page) else {
            return false
        }

        let pointOnPage = convert(pointInView, to: page)
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections

        return selections.contains { lineSelection in
            lineSelection.pages.contains(page)
                && lineSelection.bounds(for: page).insetBy(dx: -2, dy: -2).contains(pointOnPage)
        }
    }
}

extension VellumPDFView: ReaderController {}

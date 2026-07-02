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

private struct MouseTextSelectionEndpoint {
    let page: PDFPage
    let pageIndex: Int
    let characterIndex: Int
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
    var scrollBoundsObserver: NSObjectProtocol?
    weak var observedScrollClipView: NSClipView?
    var readerStateSaveWorkItem: DispatchWorkItem?
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
        updateExplanationTrackingArea()
        didDragDuringCurrentMouseSequence = false
        pendingClickHorizontalOrigin = nil
        pendingDoubleClickTextSelectionPoint = nil
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

        if linkAnnotation(at: convert(event.locationInWindow, from: nil)) == nil,
           trackMouseTextSelection(from: event) {
            return
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
        super.scrollWheel(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let didHandleDoubleClickTextSelectionMouseDown = didHandleDoubleClickTextSelectionMouseDown
        self.didHandleDoubleClickTextSelectionMouseDown = false
        if !didHandleDoubleClickTextSelectionMouseDown {
            super.mouseUp(with: event)
        }
        finishMouseSelectionSequence()
    }

    private func finishMouseSelectionSequence() {
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

    private func trackMouseTextSelection(from mouseDownEvent: NSEvent) -> Bool {
        guard mouseDownEvent.clickCount == 1,
              mouseDownEvent.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window,
              let anchor = mouseTextSelectionEndpoint(
                atWindowPoint: mouseDownEvent.locationInWindow,
                nearestPage: false,
                requiresCharacterHit: true
              ) else {
            return false
        }

        var didApplySelection = false
        var latestMouseLocation = mouseDownEvent.locationInWindow
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .scrollWheel]

        while true {
            guard let event = window.nextEvent(
                matching: eventMask,
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            switch event.type {
            case .leftMouseDragged:
                latestMouseLocation = event.locationInWindow
                pendingDoubleClickTextSelectionPoint = nil
                didHandleDoubleClickTextSelectionMouseDown = false
                didDragDuringCurrentMouseSequence = true
                pendingClickHorizontalOrigin = nil
                cancelPendingRestore()
                searchController?.markReaderNavigated()
                hideAIExplanationPopover()
                didApplySelection = updateMouseTextSelection(
                    anchor: anchor,
                    windowPoint: latestMouseLocation
                ) || didApplySelection

            case .scrollWheel:
                latestMouseLocation = event.locationInWindow
                scrollPDFViewDuringMouseSelectionTracking(with: event)
                if didDragDuringCurrentMouseSequence || didApplySelection {
                    didApplySelection = updateMouseTextSelection(
                        anchor: anchor,
                        windowPoint: latestMouseLocation
                    ) || didApplySelection
                }

            case .leftMouseUp:
                if !didApplySelection, currentSelection != nil {
                    clearSelection()
                    needsDisplay = true
                }
                finishMouseSelectionSequence()
                return true

            default:
                continue
            }
        }
    }

    @discardableResult
    private func updateMouseTextSelection(
        anchor: MouseTextSelectionEndpoint,
        windowPoint: NSPoint
    ) -> Bool {
        guard let extent = mouseTextSelectionEndpoint(
            atWindowPoint: windowPoint,
            nearestPage: true,
            requiresCharacterHit: false
        ),
              let document else {
            return false
        }

        let start: MouseTextSelectionEndpoint
        let end: MouseTextSelectionEndpoint
        if compareMouseTextSelectionEndpoint(anchor, extent) <= 0 {
            start = anchor
            end = extent
        } else {
            start = extent
            end = anchor
        }

        guard let selection = document.selection(
            from: start.page,
            atCharacterIndex: start.characterIndex,
            to: end.page,
            atCharacterIndex: end.characterIndex
        ),
        !selection.pages.isEmpty else {
            return false
        }

        setCurrentSelection(selection, animate: false)
        needsDisplay = true
        return true
    }

    private func mouseTextSelectionEndpoint(
        atWindowPoint windowPoint: NSPoint,
        nearestPage: Bool,
        requiresCharacterHit: Bool
    ) -> MouseTextSelectionEndpoint? {
        guard let document else { return nil }

        let pointInView = convert(windowPoint, from: nil)
        guard nearestPage || bounds.insetBy(dx: -4, dy: -4).contains(pointInView),
              let page = page(for: pointInView, nearest: nearestPage) else {
            return nil
        }

        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound,
              page.numberOfCharacters > 0 else {
            return nil
        }

        let pointOnPage = convert(pointInView, to: page)
        let rawCharacterIndex = page.characterIndex(at: pointOnPage)
        guard rawCharacterIndex != NSNotFound else { return nil }

        let characterIndex = min(max(rawCharacterIndex, 0), page.numberOfCharacters - 1)
        if requiresCharacterHit {
            let characterBounds = page.characterBounds(at: characterIndex).insetBy(dx: -8, dy: -8)
            guard characterBounds.contains(pointOnPage) else { return nil }
        }

        return MouseTextSelectionEndpoint(
            page: page,
            pageIndex: pageIndex,
            characterIndex: characterIndex
        )
    }

    private func compareMouseTextSelectionEndpoint(
        _ lhs: MouseTextSelectionEndpoint,
        _ rhs: MouseTextSelectionEndpoint
    ) -> Int {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex ? -1 : 1
        }
        if lhs.characterIndex == rhs.characterIndex {
            return 0
        }
        return lhs.characterIndex < rhs.characterIndex ? -1 : 1
    }

    private func scrollPDFViewDuringMouseSelectionTracking(with event: NSEvent) {
        guard let scrollView = pdfScrollView else { return }

        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        searchController?.markReaderNavigated()

        let clipView = scrollView.contentView
        let originBeforeScroll = clipView.bounds.origin
        scrollView.scrollWheel(with: event)
        if clipView.bounds.origin != originBeforeScroll {
            didDragDuringCurrentMouseSequence = true
            pendingClickHorizontalOrigin = nil
            scheduleReaderStateSave()
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

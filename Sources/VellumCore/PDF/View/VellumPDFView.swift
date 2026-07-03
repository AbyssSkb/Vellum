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

struct MouseTextSelectionEndpoint {
    let lowerOffset: Int
    let upperOffset: Int

    static func selectionRange(
        anchor: MouseTextSelectionEndpoint,
        extent: MouseTextSelectionEndpoint
    ) -> (start: Int, end: Int)? {
        let start = min(anchor.lowerOffset, extent.lowerOffset)
        let end = max(anchor.upperOffset, extent.upperOffset)
        guard end > start else { return nil }
        return (start, end)
    }
}

private struct MouseTextSelectionLineCacheKey: Hashable {
    let pageID: ObjectIdentifier
    let pageStart: Int
    let characterCount: Int
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
    private var mouseTextSelectionCacheDocumentID: ObjectIdentifier?
    private var mouseTextSelectionLineCache: [MouseTextSelectionLineCacheKey: [VimTextLine]] = [:]
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
        updateAIFloatingOverlayFrames()
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
        if trackMouseTextSelection(from: event) {
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
        guard let document else { return false }

        let documentID = ObjectIdentifier(document)
        if mouseTextSelectionCacheDocumentID != documentID {
            mouseTextSelectionCacheDocumentID = documentID
            mouseTextSelectionLineCache.removeAll()
        }

        let pageStarts = textPageStarts(in: document)
        guard pageStarts.last ?? 0 > 0 else { return false }

        guard mouseDownEvent.clickCount == 1,
              mouseDownEvent.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window,
              linkAnnotation(at: convert(mouseDownEvent.locationInWindow, from: nil)) == nil,
              let anchor = mouseTextSelectionEndpoint(
                atWindowPoint: mouseDownEvent.locationInWindow,
                nearestPage: false,
                requiresCharacterHit: true,
                pageStarts: pageStarts
              ) else {
            return false
        }

        var didApplySelection = false
        var didBeginDragSelection = false
        var latestMouseLocation = mouseDownEvent.locationInWindow
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .scrollWheel]
        let dragThreshold: CGFloat = 3

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
                didBeginDragSelection = didBeginDragSelection
                    || abs(latestMouseLocation.x - mouseDownEvent.locationInWindow.x) >= dragThreshold
                    || abs(latestMouseLocation.y - mouseDownEvent.locationInWindow.y) >= dragThreshold

                guard didBeginDragSelection else { continue }
                prepareMouseTextSelectionDrag()
                didApplySelection = updateMouseTextSelection(
                    anchor: anchor,
                    windowPoint: latestMouseLocation,
                    pageStarts: pageStarts
                ) || didApplySelection

            case .scrollWheel:
                latestMouseLocation = event.locationInWindow
                didBeginDragSelection = true
                prepareMouseTextSelectionDrag()
                scrollPDFViewDuringMouseTextSelection(with: event)
                didApplySelection = updateMouseTextSelection(
                    anchor: anchor,
                    windowPoint: latestMouseLocation,
                    pageStarts: pageStarts
                ) || didApplySelection

            case .leftMouseUp:
                if !didApplySelection {
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

    private func prepareMouseTextSelectionDrag() {
        isMouseSelectingText = true
        pendingDoubleClickTextSelectionPoint = nil
        didHandleDoubleClickTextSelectionMouseDown = false
        didDragDuringCurrentMouseSequence = true
        pendingClickHorizontalOrigin = nil
        cancelPendingRestore()
        searchController?.markReaderNavigated()
        hideAIExplanationPopover()
    }

    @discardableResult
    private func updateMouseTextSelection(
        anchor: MouseTextSelectionEndpoint,
        windowPoint: NSPoint,
        pageStarts: [Int]
    ) -> Bool {
        guard let extent = mouseTextSelectionEndpoint(
            atWindowPoint: windowPoint,
            nearestPage: true,
            requiresCharacterHit: false,
            pageStarts: pageStarts
        ),
              let range = MouseTextSelectionEndpoint.selectionRange(anchor: anchor, extent: extent) else {
            return false
        }

        return applyTextSelection(
            anchorOffset: range.start,
            extentOffset: range.end,
            pageStarts: pageStarts,
            scrollToEndpoint: false
        )
    }

    private func mouseTextSelectionEndpoint(
        atWindowPoint windowPoint: NSPoint,
        nearestPage: Bool,
        requiresCharacterHit: Bool,
        pageStarts: [Int]
    ) -> MouseTextSelectionEndpoint? {
        guard let document else { return nil }

        let pointInView = convert(windowPoint, from: nil)
        guard nearestPage || bounds.insetBy(dx: -4, dy: -4).contains(pointInView),
              let page = page(for: pointInView, nearest: nearestPage) else {
            return nil
        }

        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }

        let pointOnPage = convert(pointInView, to: page)
        return mouseTextSelectionEndpoint(
            on: page,
            pageIndex: pageIndex,
            pointOnPage: pointOnPage,
            requiresCharacterHit: requiresCharacterHit,
            pageStarts: pageStarts
        )
    }

    func mouseTextSelectionEndpoint(
        on page: PDFPage,
        pageIndex: Int,
        pointOnPage: NSPoint,
        requiresCharacterHit: Bool,
        pageStarts: [Int]
    ) -> MouseTextSelectionEndpoint? {
        guard let totalLength = pageStarts.last,
              totalLength > 0,
              pageIndex >= 0,
              pageIndex + 1 < pageStarts.count,
              page.numberOfCharacters > 0 else {
            return nil
        }

        let lines = mouseTextSelectionLines(on: page, pageIndex: pageIndex, pageStarts: pageStarts)
        if let characterEndpoint = mouseTextSelectionCharacterEndpoint(
            pointOnPage: pointOnPage,
            requiresCharacterHit: requiresCharacterHit,
            lines: lines,
            totalLength: totalLength
        ) {
            return characterEndpoint
        }

        if let line = mouseTextSelectionLine(at: pointOnPage, in: lines) {
            if requiresCharacterHit {
                guard mouseTextSelectionLine(line, contains: pointOnPage) else { return nil }
            }

            if let caret = targetCaret(in: line, preferredX: pointOnPage.x) {
                let offset = min(max(caret.offset, 0), totalLength)
                return MouseTextSelectionEndpoint(lowerOffset: offset, upperOffset: offset)
            }
        }

        return nil
    }

    private func mouseTextSelectionCharacterEndpoint(
        pointOnPage: NSPoint,
        requiresCharacterHit: Bool,
        lines: [VimTextLine],
        totalLength: Int
    ) -> MouseTextSelectionEndpoint? {
        guard let line = mouseTextSelectionLine(at: pointOnPage, in: lines) else { return nil }
        if requiresCharacterHit {
            guard mouseTextSelectionLine(line, contains: pointOnPage) else { return nil }
        }

        guard let character = mouseTextSelectionCharacter(at: pointOnPage, in: line) else {
            return nil
        }

        let lowerOffset = min(max(character.globalOffset, 0), totalLength)
        let upperOffset = min(max(lowerOffset + 1, 0), totalLength)
        return MouseTextSelectionEndpoint(lowerOffset: lowerOffset, upperOffset: upperOffset)
    }

    private func mouseTextSelectionLines(
        on page: PDFPage,
        pageIndex: Int,
        pageStarts: [Int]
    ) -> [VimTextLine] {
        guard pageIndex + 1 < pageStarts.count else { return [] }

        let pageStart = pageStarts[pageIndex]
        let cacheKey = MouseTextSelectionLineCacheKey(
            pageID: ObjectIdentifier(page),
            pageStart: pageStart,
            characterCount: page.numberOfCharacters
        )
        if let cachedLines = mouseTextSelectionLineCache[cacheKey] {
            return cachedLines
        }

        let pageText = page.string as NSString?
        var characters: [VimTextLineCharacter] = []
        for characterIndex in 0..<page.numberOfCharacters {
            guard !isNewlineCharacter(at: characterIndex, in: pageText),
                  let characterSelection = page.selection(for: NSRange(location: characterIndex, length: 1)),
                  characterSelection.string?.isEmpty == false else {
                continue
            }

            let bounds = characterSelection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            characters.append(
                VimTextLineCharacter(
                    globalOffset: pageStart + characterIndex,
                    minX: bounds.minX,
                    centerX: bounds.midX,
                    maxX: bounds.maxX,
                    centerY: bounds.midY,
                    height: bounds.height
                )
            )
        }

        let sortedCharacters = characters.sorted {
            if abs($0.centerY - $1.centerY) > 2 {
                return $0.centerY > $1.centerY
            }
            return $0.centerX < $1.centerX
        }

        var grouped: [[VimTextLineCharacter]] = []
        for character in sortedCharacters {
            if let last = grouped.indices.last,
               let reference = grouped[last].first {
                let threshold = max(2.0, max(reference.height, character.height) * 0.65)
                if abs(reference.centerY - character.centerY) <= threshold {
                    grouped[last].append(character)
                    continue
                }
            }
            grouped.append([character])
        }

        let lines = grouped.flatMap { group in
            splitVisualLineSegments(group.sorted { $0.centerX < $1.centerX }).map { lineCharacters in
                let start = lineCharacters.map(\.globalOffset).min() ?? 0
                let end = lineCharacters.map(\.globalOffset).max().map { $0 + 1 } ?? start

                let midY = lineCharacters.reduce(CGFloat(0)) { $0 + $1.centerY } / CGFloat(lineCharacters.count)
                return VimTextLine(
                    pageIndex: pageIndex,
                    startOffset: start,
                    endOffset: end,
                    midY: midY,
                    characters: lineCharacters
                )
            }
        }
        mouseTextSelectionLineCache[cacheKey] = lines
        return lines
    }

    private func mouseTextSelectionCharacter(
        at point: NSPoint,
        in line: VimTextLine
    ) -> VimTextLineCharacter? {
        let candidates = line.characters.filter { character in
            let rect = NSRect(
                x: character.minX,
                y: character.centerY - character.height / 2,
                width: max(1, character.maxX - character.minX),
                height: max(1, character.height)
            ).insetBy(dx: -1.5, dy: -4)
            return rect.contains(point)
        }

        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs.centerX - point.x)
            let rhsDistance = abs(rhs.centerX - point.x)
            if abs(lhsDistance - rhsDistance) > 0.5 {
                return lhsDistance < rhsDistance
            }

            return lhs.globalOffset < rhs.globalOffset
        }
    }

    private func mouseTextSelectionLine(
        at point: NSPoint,
        in lines: [VimTextLine]
    ) -> VimTextLine? {
        lines.min { lhs, rhs in
            let lhsVerticalDistance = abs(lhs.midY - point.y)
            let rhsVerticalDistance = abs(rhs.midY - point.y)
            let verticalTolerance = max(2, max(averageCharacterHeight(in: lhs), averageCharacterHeight(in: rhs)) * 0.35)

            if abs(lhsVerticalDistance - rhsVerticalDistance) > verticalTolerance {
                return lhsVerticalDistance < rhsVerticalDistance
            }

            let lhsHorizontalDistance = lineDistanceToX(point.x, lhs)
            let rhsHorizontalDistance = lineDistanceToX(point.x, rhs)
            if abs(lhsHorizontalDistance - rhsHorizontalDistance) > 0.5 {
                return lhsHorizontalDistance < rhsHorizontalDistance
            }

            return lhs.startOffset < rhs.startOffset
        }
    }

    private func mouseTextSelectionLine(
        _ line: VimTextLine,
        contains point: NSPoint
    ) -> Bool {
        guard let first = line.characters.first,
              let last = line.characters.last else {
            return false
        }

        let minY = line.characters.map { $0.centerY - $0.height / 2 }.min() ?? line.midY
        let maxY = line.characters.map { $0.centerY + $0.height / 2 }.max() ?? line.midY
        let verticalSlop = max(8, averageCharacterHeight(in: line) * 0.35)
        let lineBounds = NSRect(
            x: first.minX,
            y: minY,
            width: max(1, last.maxX - first.minX),
            height: max(1, maxY - minY)
        ).insetBy(dx: -8, dy: -verticalSlop)

        return lineBounds.contains(point)
    }

    private func scrollPDFViewDuringMouseTextSelection(with event: NSEvent) {
        guard let scrollView = pdfScrollView else { return }

        let clipView = scrollView.contentView
        let originBeforeScroll = clipView.bounds.origin
        scrollView.scrollWheel(with: event)
        if clipView.bounds.origin != originBeforeScroll {
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

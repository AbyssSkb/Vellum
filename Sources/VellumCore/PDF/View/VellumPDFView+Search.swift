@preconcurrency import AppKit
@preconcurrency import PDFKit

struct SearchResultLocation: Equatable {
    var pageIndex: Int
    var boundsInPage: NSRect
    var documentOrder: Int
}

struct SearchTextMatch: Equatable {
    var pageIndex: Int
    var range: NSRange
    var documentOrder: Int
}

extension SearchTextMatch {
    static func pageTextOrderSort(_ lhs: SearchTextMatch, _ rhs: SearchTextMatch) -> Bool {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex
        }

        if lhs.range.location != rhs.range.location {
            return lhs.range.location < rhs.range.location
        }

        return lhs.documentOrder < rhs.documentOrder
    }
}

enum SearchTextFinder {
    static func matches(
        in text: String,
        term: String,
        pageIndex: Int,
        startingDocumentOrder: Int
    ) -> [SearchTextMatch] {
        guard !term.isEmpty else { return [] }

        let haystack = text as NSString
        let needleLength = (term as NSString).length
        guard haystack.length > 0, needleLength > 0 else { return [] }

        var matches: [SearchTextMatch] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        var documentOrder = startingDocumentOrder

        while searchRange.length > 0 {
            let foundRange = haystack.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            matches.append(
                SearchTextMatch(
                    pageIndex: pageIndex,
                    range: foundRange,
                    documentOrder: documentOrder
                )
            )
            documentOrder += 1

            let nextLocation = foundRange.location + foundRange.length
            guard nextLocation < haystack.length else { break }
            searchRange = NSRange(
                location: nextLocation,
                length: haystack.length - nextLocation
            )
        }

        return matches
    }
}

extension SearchResultLocation {
    static func documentOrderSort(_ lhs: SearchResultLocation, _ rhs: SearchResultLocation) -> Bool {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex
        }

        let verticalTolerance: CGFloat = 2
        if abs(lhs.boundsInPage.midY - rhs.boundsInPage.midY) > verticalTolerance {
            return lhs.boundsInPage.midY > rhs.boundsInPage.midY
        }

        if lhs.boundsInPage.minX != rhs.boundsInPage.minX {
            return lhs.boundsInPage.minX < rhs.boundsInPage.minX
        }

        return lhs.documentOrder < rhs.documentOrder
    }
}

struct PDFSearchResult {
    var match: SearchTextMatch
    var selection: PDFSelection?
    var location: SearchResultLocation?

    var pageIndex: Int {
        match.pageIndex
    }

    var documentOrder: Int {
        match.documentOrder
    }

    var searchLocation: SearchResultLocation {
        location ?? SearchResultLocation(
            pageIndex: match.pageIndex,
            boundsInPage: NSRect(x: 0, y: CGFloat.greatestFiniteMagnitude, width: 1, height: 1),
            documentOrder: match.documentOrder
        )
    }
}

struct SearchAnchor: Equatable {
    var pageIndex: Int
    var pointInPage: NSPoint
}

enum SearchResultNavigator {
    enum Direction {
        case next
        case previous
    }

    static func firstIndex(atOrAfter anchor: SearchAnchor, in locations: [SearchResultLocation]) -> Int? {
        locations.firstIndex { isAtOrAfterAnchor($0, anchor: anchor) }
    }

    static func lastIndex(beforeOrAt anchor: SearchAnchor, in locations: [SearchResultLocation]) -> Int? {
        locations.lastIndex { isBeforeOrAtAnchor($0, anchor: anchor) }
    }

    static func resolvedAnchoredMoveIndex(
        anchoredIndex: Int?,
        activeIndex: Int?,
        resultCount: Int,
        direction: Direction
    ) -> Int? {
        guard resultCount > 0 else { return nil }
        guard let anchoredIndex else { return activeIndex ?? 0 }
        guard anchoredIndex == activeIndex else { return anchoredIndex }

        switch direction {
        case .next:
            return (anchoredIndex + 1) % resultCount
        case .previous:
            return (anchoredIndex + resultCount - 1) % resultCount
        }
    }

    private static func isAtOrAfterAnchor(_ location: SearchResultLocation, anchor: SearchAnchor) -> Bool {
        if location.pageIndex != anchor.pageIndex {
            return location.pageIndex > anchor.pageIndex
        }

        let verticalTolerance: CGFloat = 2
        if location.boundsInPage.maxY < anchor.pointInPage.y - verticalTolerance {
            return true
        }

        let sameLine = location.boundsInPage.minY <= anchor.pointInPage.y + verticalTolerance
            && location.boundsInPage.maxY >= anchor.pointInPage.y - verticalTolerance
        if sameLine {
            return location.boundsInPage.midX >= anchor.pointInPage.x
        }

        return false
    }

    private static func isBeforeOrAtAnchor(_ location: SearchResultLocation, anchor: SearchAnchor) -> Bool {
        if location.pageIndex != anchor.pageIndex {
            return location.pageIndex < anchor.pageIndex
        }

        let verticalTolerance: CGFloat = 2
        if location.boundsInPage.minY > anchor.pointInPage.y + verticalTolerance {
            return true
        }

        let sameLine = location.boundsInPage.minY <= anchor.pointInPage.y + verticalTolerance
            && location.boundsInPage.maxY >= anchor.pointInPage.y - verticalTolerance
        if sameLine {
            return location.boundsInPage.midX <= anchor.pointInPage.x
        }

        return false
    }
}

extension VellumPDFView {
    func beginSearchCommand() {
        guard document != nil else { return }

        if searchController == nil {
            searchController = PDFSearchController(pdfView: self)
        }

        searchController?.begin()
    }

    func vimSearchNext() {
        searchController?.move(.next)
    }

    func vimSearchPrevious() {
        searchController?.move(.previous)
    }

    func vimMaterializeSearchSelection() {
        searchController?.materializeActiveMatch()
    }
}

@MainActor
final class PDFSearchController {
    private static let debounceDelay: TimeInterval = 0.16
    private static let jumpCoalescingInterval: TimeInterval = 1.0
    private static let inactiveMatchColor = TokyoNight.blue.withAlphaComponent(0.32)
    private static let activeMatchColor = NSColor(calibratedRed: 1.0, green: 0.64, blue: 0.20, alpha: 0.58)

    enum Direction {
        case next
        case previous
    }

    private func navigatorDirection(for direction: Direction) -> SearchResultNavigator.Direction {
        switch direction {
        case .next:
            return .next
        case .previous:
            return .previous
        }
    }

    nonisolated static func index(of activeMatch: SearchTextMatch?, in results: [PDFSearchResult]) -> Int? {
        guard let activeMatch else { return nil }
        return results.firstIndex { $0.match == activeMatch }
    }

    private weak var pdfView: VellumPDFView?
    private var overlay: SearchCommandOverlayView?
    private var query = ""
    private var results: [PDFSearchResult] = []
    private var activeIndex: Int?
    private var areMatchesVisible = false
    private var shouldAnchorNextMove = false
    private var debounceTimer: Timer?
    private var previewSearchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var isSearchPending = false
    private var lastJumpCheckpointTime: Date?
    private var pageTextCache: [Int: String] = [:]

    var hasVisibleHighlights: Bool {
        areMatchesVisible && !results.isEmpty
    }

    var hasTextTarget: Bool {
        activeIndex != nil && !results.isEmpty
    }

    var canHandleEscape: Bool {
        overlay != nil || !results.isEmpty || !query.isEmpty || isSearchPending
    }

    init(pdfView: VellumPDFView) {
        self.pdfView = pdfView
    }

    func begin() {
        guard let pdfView, pdfView.document != nil else { return }

        pdfView.stopScrollAnimation()
        pdfView.hideAIExplanationPopover()

        if !hasVisibleHighlights {
            resetSearchStateForNewCommand()
        }

        let overlay = SearchCommandOverlayView(query: query)
        overlay.frame = pdfView.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.onQueryChanged = { [weak self] query in
            self?.update(query: query, resetSelection: true)
        }
        overlay.onCommit = { [weak self] in
            self?.commit()
        }
        overlay.onCancel = { [weak self] in
            self?.cancel()
        }

        self.overlay?.removeFromSuperview()
        pdfView.addSubview(overlay)
        self.overlay = overlay

        updateOverlayStatus()
        overlay.focus()
    }

    func move(_ direction: Direction) {
        if results.isEmpty || isSearchPending {
            performSearchImmediately(preferAnchor: false, materializeVisibleMatches: false)
        } else {
            cancelScheduledSearch()
            isSearchPending = false
        }
        guard !results.isEmpty else { return }

        areMatchesVisible = true
        if shouldAnchorNextMove {
            activeIndex = SearchResultNavigator.resolvedAnchoredMoveIndex(
                anchoredIndex: anchoredIndex(for: direction, materializeLocations: true),
                activeIndex: activeIndex,
                resultCount: results.count,
                direction: navigatorDirection(for: direction)
            )
        } else {
            let current = activeIndex ?? anchoredIndex(for: direction, materializeLocations: true) ?? 0
            switch direction {
            case .next:
                activeIndex = (current + 1) % results.count
            case .previous:
                activeIndex = (current + results.count - 1) % results.count
            }
        }
        shouldAnchorNextMove = false

        materializeVisibleMatchesAroundActive()
        applyVisibleHighlights()
        ensureMiniOverlay()
        updateOverlayStatus()
        jumpToSelectedMatch(recordJump: true)
    }

    func markReaderNavigated() {
        shouldAnchorNextMove = true
    }

    @discardableResult
    func handleEscape() -> Bool {
        if overlay != nil {
            dismissOverlay(returnFocus: true)
            if results.isEmpty {
                clear()
            } else {
                hideMatches()
            }
            return true
        }

        if hasVisibleHighlights {
            hideMatches()
            return true
        }

        if !results.isEmpty || !query.isEmpty || isSearchPending {
            clear()
            return true
        }

        return false
    }

    @discardableResult
    func materializeActiveMatch() -> Bool {
        guard let pdfView, let selection = activeSearchSelection else {
            NSSound.beep()
            return false
        }

        let materializedSelection = selection.copy() as? PDFSelection ?? selection
        materializedSelection.color = nil
        hideMatches()
        pdfView.textSelectionNavigationState = nil
        pdfView.setCurrentSelection(materializedSelection, animate: false)
        pdfView.focus()
        return true
    }

    func hideMatchesAfterTextAction() {
        guard activeSearchSelection != nil else { return }
        hideMatches()
    }

    var activeSearchSelection: PDFSelection? {
        guard let activeIndex, results.indices.contains(activeIndex) else { return nil }
        return materializedSelection(at: activeIndex)
    }

    private func update(query nextQuery: String, resetSelection: Bool) {
        query = nextQuery
        searchGeneration += 1
        debounceTimer?.invalidate()
        previewSearchTask?.cancel()
        lastJumpCheckpointTime = nil

        guard let pdfView, pdfView.document != nil else {
            results = []
            activeIndex = nil
            areMatchesVisible = false
            shouldAnchorNextMove = false
            isSearchPending = false
            updateOverlayStatus()
            return
        }

        let term = nextQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            activeIndex = nil
            areMatchesVisible = false
            shouldAnchorNextMove = false
            isSearchPending = false
            pdfView.highlightedSelections = []
            updateOverlayStatus()
            previewSearchTask = nil
            return
        }

        isSearchPending = true
        results = []
        activeIndex = nil
        areMatchesVisible = false
        shouldAnchorNextMove = false
        pdfView.highlightedSelections = []
        scheduleSearch(generation: searchGeneration, preferAnchor: resetSelection)
        updateOverlayStatus()
    }

    private func commit() {
        performSearchImmediately(preferAnchor: true, materializeVisibleMatches: true)
        guard !results.isEmpty else {
            updateOverlayStatus()
            return
        }

        areMatchesVisible = true
        materializeVisibleMatchesAroundActive()
        applyVisibleHighlights()
        updateOverlayStatus()
        overlay?.showMini(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        pdfView?.focus()
        jumpToSelectedMatch(recordJump: true)
    }

    private func cancel() {
        _ = handleEscape()
    }

    func clear() {
        cancelScheduledSearch()
        resetSearchStateForNewCommand()
        pdfView?.highlightedSelections = []
    }

    private func resetSearchStateForNewCommand() {
        searchGeneration += 1
        query = ""
        results = []
        activeIndex = nil
        areMatchesVisible = false
        shouldAnchorNextMove = false
        isSearchPending = false
        lastJumpCheckpointTime = nil
    }

    private func hideMatches() {
        areMatchesVisible = false
        pdfView?.highlightedSelections = []
        dismissOverlay(returnFocus: false)
        updateOverlayStatus()
    }

    private func dismissOverlay(returnFocus: Bool) {
        overlay?.removeFromSuperview()
        overlay = nil

        if returnFocus {
            pdfView?.focus()
        }
    }

    private func jumpToSelectedMatch(recordJump: Bool) {
        guard let pdfView,
              let activeIndex,
              results.indices.contains(activeIndex) else { return }

        guard let selection = materializedSelection(at: activeIndex) else {
            NSSound.beep()
            return
        }

        pdfView.cancelPendingRestore()
        if recordJump, shouldRecordJumpCheckpoint() {
            pdfView.recordJumpSource()
        }
        pdfView.stopScrollAnimation()
        pdfView.stopZoomState()
        pdfView.go(to: selection)

        DispatchQueue.main.async { [weak self, weak pdfView, weak selection] in
            guard let self, let pdfView, let selection else { return }
            pdfView.go(to: selection)
            self.shouldAnchorNextMove = false
        }
    }

    private func shouldRecordJumpCheckpoint() -> Bool {
        let now = Date()
        defer { lastJumpCheckpointTime = now }

        guard let lastJumpCheckpointTime else { return true }
        return now.timeIntervalSince(lastJumpCheckpointTime) > Self.jumpCoalescingInterval
    }

    private func scheduleSearch(generation: Int, preferAnchor: Bool) {
        previewSearchTask?.cancel()
        let timer = Timer(timeInterval: Self.debounceDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.searchGeneration == generation else { return }
                self.startPreviewSearch(
                    generation: generation,
                    preferAnchor: preferAnchor
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        debounceTimer = timer
    }

    private func performSearchImmediately(preferAnchor: Bool, materializeVisibleMatches: Bool) {
        cancelScheduledSearch()
        searchGeneration += 1
        let activeMatch = activeIndex.flatMap { index in
            results.indices.contains(index) ? results[index].match : nil
        }

        guard let pdfView, let document = pdfView.document else {
            results = []
            activeIndex = nil
            areMatchesVisible = false
            shouldAnchorNextMove = false
            isSearchPending = false
            updateOverlayStatus()
            return
        }

        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            activeIndex = nil
            areMatchesVisible = false
            shouldAnchorNextMove = false
            isSearchPending = false
            pdfView.highlightedSelections = []
            updateOverlayStatus()
            return
        }

        isSearchPending = false
        let matches = textMatches(for: term, in: document)
        results = matches.map { PDFSearchResult(match: $0, selection: nil, location: nil) }

        if results.isEmpty {
            activeIndex = nil
            areMatchesVisible = false
        } else if preferAnchor {
            activeIndex = Self.index(of: activeMatch, in: results)
                ?? anchoredIndex(for: .next, materializeLocations: materializeVisibleMatches)
                ?? 0
            areMatchesVisible = true
        } else if let activeIndex {
            self.activeIndex = Self.index(of: activeMatch, in: results)
                ?? min(activeIndex, results.count - 1)
        } else {
            activeIndex = anchoredIndex(for: .next, materializeLocations: materializeVisibleMatches) ?? 0
        }

        if materializeVisibleMatches {
            materializeVisibleMatchesAroundActive()
        }
        applyVisibleHighlights()
        updateOverlayStatus()
    }

    private func startPreviewSearch(generation: Int, preferAnchor: Bool) {
        previewSearchTask?.cancel()
        previewSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let document = self.pdfView?.document else {
                self.publishPreviewResults([], preferAnchor: preferAnchor, isComplete: true)
                return
            }

            var previewResults: [PDFSearchResult] = []
            var lastPublish = Date.distantPast
            let pageCount = document.pageCount
            let term = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let anchorPageIndex = self.currentSearchAnchor(in: document).pageIndex
            let pageScanOrder = Self.previewPageScanOrder(
                pageCount: pageCount,
                anchorPageIndex: anchorPageIndex
            )

            guard !term.isEmpty else {
                self.publishPreviewResults([], preferAnchor: preferAnchor, isComplete: true)
                return
            }

            for (scanIndex, pageIndex) in pageScanOrder.enumerated() {
                guard !Task.isCancelled, self.searchGeneration == generation else { return }

                if let text = self.pageText(pageIndex: pageIndex, in: document) {
                    let pageMatches = SearchTextFinder.matches(
                        in: text,
                        term: term,
                        pageIndex: pageIndex,
                        startingDocumentOrder: previewResults.count
                    )
                    previewResults.append(
                        contentsOf: pageMatches.map {
                            PDFSearchResult(match: $0, selection: nil, location: nil)
                        }
                    )
                }

                let isComplete = scanIndex == pageScanOrder.count - 1
                let shouldPublish = isComplete
                    || scanIndex == 0
                    || Date().timeIntervalSince(lastPublish) > 0.035

                if shouldPublish {
                    self.publishPreviewResults(
                        previewResults,
                        preferAnchor: preferAnchor,
                        isComplete: isComplete
                    )
                    lastPublish = Date()
                }

                await Task.yield()
            }
        }
    }

    nonisolated static func previewPageScanOrder(pageCount: Int, anchorPageIndex: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let anchor = min(max(anchorPageIndex, 0), pageCount - 1)
        return [anchor]
            + Array((anchor + 1)..<pageCount)
            + Array(0..<anchor)
    }

    private func publishPreviewResults(
        _ nextResults: [PDFSearchResult],
        preferAnchor: Bool,
        isComplete: Bool
    ) {
        let hadActiveResult = activeIndex != nil && !results.isEmpty
        results = nextResults.sorted {
            SearchTextMatch.pageTextOrderSort($0.match, $1.match)
        }
        isSearchPending = !isComplete

        if results.isEmpty {
            activeIndex = nil
            areMatchesVisible = false
        } else if preferAnchor || activeIndex == nil {
            activeIndex = anchoredIndex(for: .next, materializeLocations: true) ?? 0
            areMatchesVisible = true
        } else if let activeIndex {
            self.activeIndex = min(activeIndex, results.count - 1)
            materializeVisibleMatchesAroundActive()
            areMatchesVisible = true
        }

        if areMatchesVisible {
            materializeVisibleMatchesAroundActive()
        }
        applyVisibleHighlights()
        updateOverlayStatus()

        if preferAnchor, !hadActiveResult, activeIndex != nil {
            jumpToSelectedMatch(recordJump: false)
        }
    }

    private func cancelScheduledSearch() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        previewSearchTask?.cancel()
        previewSearchTask = nil
    }

    private func textMatches(for term: String, in document: PDFDocument) -> [SearchTextMatch] {
        var matches: [SearchTextMatch] = []
        for pageIndex in 0..<document.pageCount {
            guard let text = pageText(pageIndex: pageIndex, in: document) else { continue }
            let pageMatches = SearchTextFinder.matches(
                in: text,
                term: term,
                pageIndex: pageIndex,
                startingDocumentOrder: matches.count
            )
            matches.append(contentsOf: pageMatches)
        }
        return matches
    }

    private func pageText(pageIndex: Int, in document: PDFDocument) -> String? {
        if let cached = pageTextCache[pageIndex] {
            return cached
        }

        guard let text = document.page(at: pageIndex)?.string else { return nil }
        pageTextCache[pageIndex] = text
        return text
    }

    private func materializedSelectionIfCached(at index: Int) -> PDFSelection? {
        guard results.indices.contains(index) else { return nil }
        return results[index].selection
    }

    private func materializedSelection(at index: Int) -> PDFSelection? {
        guard let pdfView, let document = pdfView.document, results.indices.contains(index) else { return nil }
        if let selection = results[index].selection {
            return selection
        }

        guard let page = document.page(at: results[index].match.pageIndex),
              let selection = page.selection(for: results[index].match.range) else {
            return nil
        }

        let lineSelection = selection.selectionsByLine().first ?? selection
        let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page)
            ?? selection.bounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        results[index].selection = selection
        results[index].location = SearchResultLocation(
            pageIndex: results[index].match.pageIndex,
            boundsInPage: bounds,
            documentOrder: results[index].match.documentOrder
        )
        return selection
    }

    private func materializeVisibleMatchesAroundActive() {
        guard let activeIndex, results.indices.contains(activeIndex) else { return }
        _ = materializedSelection(at: activeIndex)
        let activePageIndex = results[activeIndex].pageIndex
        for index in results.indices {
            guard abs(results[index].pageIndex - activePageIndex) <= 1 else { continue }
            _ = materializedSelection(at: index)
        }
    }

    private func anchoredIndex(for direction: Direction, materializeLocations: Bool) -> Int? {
        guard let pdfView, let document = pdfView.document, !results.isEmpty else { return nil }
        let anchor = currentSearchAnchor(in: document)
        if materializeLocations {
            materializeMatches(on: anchor.pageIndex)
        }
        let locations = results.map(\.searchLocation)
        switch direction {
        case .next:
            return SearchResultNavigator.firstIndex(atOrAfter: anchor, in: locations) ?? 0
        case .previous:
            return SearchResultNavigator.lastIndex(beforeOrAt: anchor, in: locations) ?? results.count - 1
        }
    }

    private func materializeMatches(on pageIndex: Int) {
        for index in results.indices where results[index].pageIndex == pageIndex {
            _ = materializedSelection(at: index)
        }
    }

    private func applyVisibleHighlights() {
        guard let pdfView else { return }
        guard areMatchesVisible else {
            pdfView.highlightedSelections = []
            return
        }

        let highlighted = results.indices.compactMap { index -> PDFSelection? in
            guard let selection = materializedSelectionIfCached(at: index) else { return nil }
            selection.color = index == activeIndex
                ? Self.activeMatchColor
                : Self.inactiveMatchColor
            return selection
        }
        pdfView.highlightedSelections = highlighted
    }

    private func currentSearchAnchor(in document: PDFDocument) -> SearchAnchor {
        guard let pdfView else {
            return SearchAnchor(pageIndex: 0, pointInPage: .zero)
        }

        if let selection = pdfView.currentSelection,
           let page = selection.pages.last {
            let pageIndex = document.index(for: page)
            if pageIndex != NSNotFound {
                let bounds = selection.bounds(for: page)
                if !bounds.isEmpty {
                    return SearchAnchor(
                        pageIndex: pageIndex,
                        pointInPage: NSPoint(x: bounds.maxX, y: bounds.minY)
                    )
                }
            }
        }

        if let scrollView = pdfView.pdfScrollView {
            let clipView = scrollView.contentView
            let anchorPoint = NSPoint(
                x: clipView.bounds.midX,
                y: SearchReadingAnchor.pointY(
                    visibleMinY: clipView.bounds.minY,
                    visibleHeight: clipView.bounds.height,
                    isFlipped: clipView.isFlipped
                )
            )
            let pointInPDFView = pdfView.convert(anchorPoint, from: clipView)

            if let page = pdfView.page(for: pointInPDFView, nearest: true) {
                let pageIndex = document.index(for: page)
                if pageIndex != NSNotFound {
                    return SearchAnchor(
                        pageIndex: min(max(pageIndex, 0), document.pageCount - 1),
                        pointInPage: pdfView.convert(pointInPDFView, to: page)
                    )
                }
            }
        }

        if let page = pdfView.currentPage {
            let index = document.index(for: page)
            if index != NSNotFound {
                return SearchAnchor(
                    pageIndex: min(max(index, 0), document.pageCount - 1),
                    pointInPage: NSPoint(
                        x: page.bounds(for: .cropBox).midX,
                        y: page.bounds(for: .cropBox).midY
                    )
                )
            }
        }

        return SearchAnchor(pageIndex: 0, pointInPage: .zero)
    }

    private func updateOverlayStatus() {
        overlay?.update(status: overlayStatus())
    }

    private func overlayStatus() -> SearchCommandOverlayView.Status {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .hint("type")
        } else if isSearchPending, !results.isEmpty {
            let displayIndex = activeIndex ?? anchoredIndex(for: .next, materializeLocations: false) ?? 0
            return .hint("\(displayIndex + 1)/\(results.count)...")
        } else if isSearchPending {
            return .hint("...")
        } else if results.isEmpty {
            return .error("no match")
        } else {
            let displayIndex = activeIndex ?? anchoredIndex(for: .next, materializeLocations: false) ?? 0
            return .count(current: displayIndex + 1, total: results.count)
        }
    }

    private func ensureMiniOverlay() {
        guard overlay == nil, let pdfView else { return }

        let overlay = SearchCommandOverlayView(query: query)
        overlay.frame = pdfView.bounds
        overlay.autoresizingMask = [.width, .height]
        pdfView.addSubview(overlay)
        self.overlay = overlay
        overlay.update(status: overlayStatus())
        overlay.showMini(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@MainActor
private final class SearchCommandOverlayView: NSView, NSTextFieldDelegate {
    private enum Presentation {
        case editing
        case mini
    }

    enum Status {
        case hint(String)
        case error(String)
        case count(current: Int, total: Int)

        var text: String {
            switch self {
            case .hint(let text), .error(let text):
                return text
            case .count(let current, let total):
                return "\(current)/\(total)"
            }
        }

        var color: NSColor {
            switch self {
            case .hint:
                return TokyoNight.muted
            case .error:
                return TokyoNight.red
            case .count:
                return TokyoNight.cyan
            }
        }

        var accentColor: NSColor {
            switch self {
            case .hint:
                return TokyoNight.blue.withAlphaComponent(0.18)
            case .error:
                return TokyoNight.red.withAlphaComponent(0.24)
            case .count:
                return TokyoNight.cyan.withAlphaComponent(0.24)
            }
        }
    }

    var onQueryChanged: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    private let container = NSVisualEffectView()
    private let miniContainer = NSVisualEffectView()
    private let miniLabel = CenteredTextLabel(text: "")
    private let iconView = NSImageView()
    private let textField = SearchCommandTextField()
    private let statusPill = NSVisualEffectView()
    private let statusLabel = CenteredTextLabel(text: "type")
    private var presentation: Presentation = .editing
    private var currentStatus: Status = .hint("type")
    private var miniQuery = ""

    init(query: String) {
        super.init(frame: .zero)
        wantsLayer = false
        configureContainer()
        configureLabels()
        configureTextField(query: query)

        addSubview(container)
        addSubview(miniContainer)
        container.addSubview(iconView)
        container.addSubview(textField)
        container.addSubview(statusPill)
        statusPill.addSubview(statusLabel)
        miniContainer.addSubview(miniLabel)
        updatePresentation(animated: false)

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 1
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        let horizontalMargin: CGFloat = 20
        let height: CGFloat = 44
        let width = min(max(bounds.width * 0.46, 460), bounds.width - horizontalMargin * 2, 720)
        container.frame = NSRect(
            x: bounds.midX - width / 2,
            y: 24,
            width: width,
            height: height
        )

        let centerY = container.bounds.midY
        iconView.frame = centeredFrame(x: 16, size: NSSize(width: 16, height: 16), in: container.bounds)
        let statusPillWidth = min(max(measuredWidth(statusLabel.stringValue, font: statusLabel.font) + 24, 62), 130)
        statusPill.frame = NSRect(
            x: container.bounds.maxX - statusPillWidth - 12,
            y: centerY - 14,
            width: statusPillWidth,
            height: 28
        )
        statusLabel.frame = NSRect(
            x: 12,
            y: 0,
            width: statusPill.bounds.width - 24,
            height: statusPill.bounds.height
        )
        textField.frame = NSRect(
            x: iconView.frame.maxX + 14,
            y: centerY - 13,
            width: max(120, statusPill.frame.minX - iconView.frame.maxX - 28),
            height: 26
        )

        let miniWidth = min(max(measuredWidth(miniLabel.stringValue, font: miniLabel.font) + 34, 128), bounds.width - horizontalMargin * 2, 360)
        miniContainer.frame = NSRect(
            x: bounds.midX - miniWidth / 2,
            y: 24,
            width: miniWidth,
            height: 34
        )
        miniLabel.frame = centeredTextFrame(
            x: 17,
            width: miniContainer.bounds.width - 34,
            height: miniContainer.bounds.height,
            in: miniContainer.bounds
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInContainer = convert(point, to: container)
        guard container.bounds.contains(pointInContainer) else { return nil }
        return super.hitTest(point)
    }

    func focus() {
        layoutSubtreeIfNeeded()
        showEditing()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textField)
            self.textField.currentEditor()?.selectedRange = NSRange(
                location: self.textField.stringValue.count,
                length: 0
            )
        }
    }

    func update(status: Status) {
        currentStatus = status
        statusLabel.stringValue = status.text
        statusLabel.textColor = status.color
        statusPill.layer?.borderColor = status.accentColor.cgColor
        updateMiniLabel()
        needsLayout = true
    }

    func showMini(query: String) {
        miniQuery = query
        updateMiniLabel()
        presentation = .mini
        updatePresentation(animated: true)
        needsLayout = true
    }

    private func showEditing() {
        presentation = .editing
        updatePresentation(animated: false)
    }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChanged?(textField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch SearchCommandEditingCommand.action(for: commandSelector) {
        case .commit:
            onCommit?()
            return true
        case .cancel:
            onCancel?()
            return true
        case nil:
            return false
        }
    }

    private func configureContainer() {
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.backgroundColor = TokyoNight.panelElevated.withAlphaComponent(0.10).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 14
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.18
        container.layer?.shadowRadius = 20
        container.layer?.shadowOffset = NSSize(width: 0, height: 6)

        miniContainer.material = .hudWindow
        miniContainer.blendingMode = .withinWindow
        miniContainer.state = .active
        miniContainer.wantsLayer = true
        miniContainer.layer?.backgroundColor = TokyoNight.panelElevated.withAlphaComponent(0.12).cgColor
        miniContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        miniContainer.layer?.borderWidth = 1
        miniContainer.layer?.cornerRadius = 17
        miniContainer.layer?.shadowColor = NSColor.black.cgColor
        miniContainer.layer?.shadowOpacity = 0.16
        miniContainer.layer?.shadowRadius = 16
        miniContainer.layer?.shadowOffset = NSSize(width: 0, height: 5)
    }

    private func configureLabels() {
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.contentTintColor = TokyoNight.cyan.withAlphaComponent(0.78)

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = TokyoNight.muted.withAlphaComponent(0.95)
        miniLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        miniLabel.textColor = TokyoNight.foreground.withAlphaComponent(0.94)
        miniLabel.lineBreakMode = .byTruncatingMiddle

        statusPill.material = .hudWindow
        statusPill.blendingMode = .withinWindow
        statusPill.state = .active
        statusPill.wantsLayer = true
        statusPill.layer?.backgroundColor = TokyoNight.backgroundDeep.withAlphaComponent(0.22).cgColor
        statusPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        statusPill.layer?.borderWidth = 1
        statusPill.layer?.cornerRadius = 13
    }

    private func configureTextField(query: String) {
        textField.cell = VerticallyCenteredTextFieldCell(textCell: "")
        textField.stringValue = query
        textField.font = .systemFont(ofSize: 14, weight: .medium)
        textField.textColor = TokyoNight.foreground
        textField.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [
                .foregroundColor: TokyoNight.muted,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
        )
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.focusRingType = .none
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.delegate = self
        textField.onCommit = { [weak self] in
            self?.onCommit?()
        }
        textField.onCancel = { [weak self] in
            self?.onCancel?()
        }
    }

    private func updateMiniLabel() {
        let queryText = miniQuery.isEmpty ? textField.stringValue : miniQuery
        let statusText = currentStatus.text
        miniLabel.stringValue = queryText.isEmpty ? statusText : "\(queryText)  \(statusText)"
    }

    private func updatePresentation(animated: Bool) {
        let showEditing = presentation == .editing
        let changes = {
            self.container.alphaValue = showEditing ? 1 : 0
            self.miniContainer.alphaValue = showEditing ? 0 : 1
        }

        container.isHidden = false
        miniContainer.isHidden = false
        guard animated else {
            changes()
            container.isHidden = !showEditing
            miniContainer.isHidden = showEditing
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            changes()
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.container.isHidden = !showEditing
                self.miniContainer.isHidden = showEditing
            }
        }
    }

    private func centeredFrame(x: CGFloat, size: NSSize, in bounds: NSRect) -> NSRect {
        NSRect(
            x: x,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func centeredTextFrame(x: CGFloat, width: CGFloat, height: CGFloat, in bounds: NSRect) -> NSRect {
        NSRect(
            x: x,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil(text.size(withAttributes: [.font: font]).width)
    }
}

enum SearchCommandEditingAction: Equatable {
    case commit
    case cancel
}

enum SearchCommandEditingCommand {
    static func action(for selector: Selector) -> SearchCommandEditingAction? {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return .commit
        case #selector(NSResponder.cancelOperation(_:)):
            return .cancel
        default:
            return nil
        }
    }
}

private final class CenteredTextLabel: NSView {
    var stringValue: String {
        didSet { needsDisplay = true }
    }

    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize) {
        didSet { needsDisplay = true }
    }

    var textColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    var lineBreakMode: NSLineBreakMode = .byClipping {
        didSet { needsDisplay = true }
    }

    init(text: String) {
        self.stringValue = text
        super.init(frame: .zero)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = lineBreakMode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        let size = stringValue.size(withAttributes: attributes)
        let drawRect = NSRect(
            x: 0,
            y: (bounds.height - size.height) / 2,
            width: bounds.width,
            height: size.height
        )
        stringValue.draw(in: drawRect, withAttributes: attributes)
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        verticallyCenteredRect(super.drawingRect(forBounds: rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(
            withFrame: verticallyCenteredRect(rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: verticallyCenteredRect(rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func verticallyCenteredRect(_ rect: NSRect) -> NSRect {
        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.boundingRectForFont.height) + 2
        let height = min(rect.height, textHeight)
        return NSRect(
            x: rect.minX,
            y: rect.midY - height / 2,
            width: rect.width,
            height: height
        )
    }
}

private final class SearchCommandTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

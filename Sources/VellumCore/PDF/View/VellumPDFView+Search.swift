@preconcurrency import AppKit
import PDFKit

struct SearchResultLocation: Equatable {
    var pageIndex: Int
    var boundsInPage: NSRect
    var documentOrder: Int
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
    var selection: PDFSelection
    var location: SearchResultLocation
}

struct SearchAnchor: Equatable {
    var pageIndex: Int
    var pointInPage: NSPoint
}

enum SearchResultNavigator {
    static func firstIndex(atOrAfter anchor: SearchAnchor, in locations: [SearchResultLocation]) -> Int? {
        locations.firstIndex { isAtOrAfterAnchor($0, anchor: anchor) }
    }

    static func lastIndex(beforeOrAt anchor: SearchAnchor, in locations: [SearchResultLocation]) -> Int? {
        locations.lastIndex { isBeforeOrAtAnchor($0, anchor: anchor) }
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

    private weak var pdfView: VellumPDFView?
    private var overlay: SearchCommandOverlayView?
    private var query = ""
    private var results: [PDFSearchResult] = []
    private var activeIndex: Int?
    private var areMatchesVisible = false
    private var shouldAnchorNextMove = false
    private var debounceTimer: Timer?
    private var searchGeneration = 0
    private var isSearchPending = false
    private var lastJumpCheckpointTime: Date?

    var hasVisibleHighlights: Bool {
        areMatchesVisible && !results.isEmpty
    }

    var hasTextTarget: Bool {
        activeSearchSelection != nil
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
        performSearchImmediately(preferAnchor: false)
        guard !results.isEmpty else { return }

        areMatchesVisible = true
        if shouldAnchorNextMove {
            activeIndex = anchoredIndex(for: direction) ?? activeIndex ?? 0
        } else {
            let current = activeIndex ?? anchoredIndex(for: direction) ?? 0
            switch direction {
            case .next:
                activeIndex = (current + 1) % results.count
            case .previous:
                activeIndex = (current + results.count - 1) % results.count
            }
        }
        shouldAnchorNextMove = false

        applyVisibleHighlights()
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
        return results[activeIndex].selection
    }

    private func update(query nextQuery: String, resetSelection: Bool) {
        query = nextQuery
        searchGeneration += 1
        debounceTimer?.invalidate()
        lastJumpCheckpointTime = nil

        guard let pdfView, let document = pdfView.document else {
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
            return
        }

        isSearchPending = true
        scheduleSearch(generation: searchGeneration, preferAnchor: resetSelection, document: document)
        updateOverlayStatus()
    }

    private func commit() {
        performSearchImmediately(preferAnchor: true)
        guard !results.isEmpty else {
            updateOverlayStatus()
            return
        }

        dismissOverlay(returnFocus: true)
        areMatchesVisible = true
        applyVisibleHighlights()
        jumpToSelectedMatch(recordJump: true)
    }

    private func cancel() {
        _ = handleEscape()
    }

    func clear() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        searchGeneration += 1
        query = ""
        results = []
        activeIndex = nil
        areMatchesVisible = false
        shouldAnchorNextMove = false
        isSearchPending = false
        lastJumpCheckpointTime = nil
        pdfView?.highlightedSelections = []
    }

    private func hideMatches() {
        areMatchesVisible = false
        pdfView?.highlightedSelections = []
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

        let selection = results[activeIndex].selection

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

    private func scheduleSearch(generation: Int, preferAnchor: Bool, document: PDFDocument) {
        let timer = Timer(timeInterval: Self.debounceDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.searchGeneration == generation else { return }
                self.performSearchImmediately(preferAnchor: preferAnchor)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        debounceTimer = timer
    }

    private func performSearchImmediately(preferAnchor: Bool) {
        debounceTimer?.invalidate()
        debounceTimer = nil

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
        let selections = document.findString(
            term,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )
        results = searchResults(from: selections, in: document)

        if results.isEmpty {
            activeIndex = nil
            areMatchesVisible = false
        } else if preferAnchor {
            activeIndex = anchoredIndex(for: .next) ?? 0
            areMatchesVisible = true
        } else if let activeIndex {
            self.activeIndex = min(activeIndex, results.count - 1)
        } else {
            activeIndex = anchoredIndex(for: .next) ?? 0
        }

        applyVisibleHighlights()
        updateOverlayStatus()
    }

    private func searchResults(from selections: [PDFSelection], in document: PDFDocument) -> [PDFSearchResult] {
        selections.enumerated().compactMap { documentOrder, selection in
            guard let page = selection.pages.first else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }

            let lineSelection = selection.selectionsByLine().first ?? selection
            let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page)
                ?? selection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            return PDFSearchResult(
                selection: selection,
                location: SearchResultLocation(
                    pageIndex: pageIndex,
                    boundsInPage: bounds,
                    documentOrder: documentOrder
                )
            )
        }
        .sorted {
            SearchResultLocation.documentOrderSort($0.location, $1.location)
        }
    }

    private func anchoredIndex(for direction: Direction) -> Int? {
        guard let pdfView, let document = pdfView.document, !results.isEmpty else { return nil }
        let anchor = currentSearchAnchor(in: document)
        let locations = results.map(\.location)
        switch direction {
        case .next:
            return SearchResultNavigator.firstIndex(atOrAfter: anchor, in: locations) ?? 0
        case .previous:
            return SearchResultNavigator.lastIndex(beforeOrAt: anchor, in: locations) ?? results.count - 1
        }
    }

    private func applyVisibleHighlights() {
        guard let pdfView else { return }
        guard areMatchesVisible else {
            pdfView.highlightedSelections = []
            return
        }

        let highlighted = results.enumerated().map { index, result in
            result.selection.color = index == activeIndex
                ? Self.activeMatchColor
                : Self.inactiveMatchColor
            return result.selection
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

        if let snapshot = pdfView.snapshot() {
            return SearchAnchor(
                pageIndex: min(max(snapshot.pageIndex, 0), document.pageCount - 1),
                pointInPage: snapshot.pointOnPage
            )
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
        let status: SearchCommandOverlayView.Status
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .hint("Type to search")
        } else if isSearchPending {
            status = .hint("Searching")
        } else if results.isEmpty {
            status = .error("No matches")
        } else {
            let displayIndex = activeIndex ?? anchoredIndex(for: .next) ?? 0
            status = .count(current: displayIndex + 1, total: results.count)
        }

        overlay?.update(status: status)
    }
}

@MainActor
private final class SearchCommandOverlayView: NSView, NSTextFieldDelegate {
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
    }

    var onQueryChanged: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    private let container = NSVisualEffectView()
    private let iconView = NSImageView()
    private let promptLabel = NSTextField(labelWithString: "/")
    private let textField = SearchCommandTextField()
    private let statusLabel = NSTextField(labelWithString: "Type to search")

    init(query: String) {
        super.init(frame: .zero)
        wantsLayer = false
        configureContainer()
        configureLabels()
        configureTextField(query: query)

        addSubview(container)
        container.addSubview(iconView)
        container.addSubview(promptLabel)
        container.addSubview(textField)
        container.addSubview(statusLabel)

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

        let width = min(max(bounds.width * 0.44, 380), 640)
        let height: CGFloat = 46
        container.frame = NSRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height - 18,
            width: width,
            height: height
        )

        iconView.frame = NSRect(x: 15, y: 14, width: 18, height: 18)
        promptLabel.frame = NSRect(x: iconView.frame.maxX + 10, y: 12, width: 16, height: 22)
        statusLabel.sizeToFit()
        let statusWidth = min(max(statusLabel.frame.width, 64), 128)
        statusLabel.frame = NSRect(
            x: container.bounds.maxX - statusWidth - 16,
            y: 12,
            width: statusWidth,
            height: 22
        )
        textField.frame = NSRect(
            x: promptLabel.frame.maxX + 10,
            y: 11,
            width: max(80, statusLabel.frame.minX - promptLabel.frame.maxX - 22),
            height: 24
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInContainer = convert(point, to: container)
        guard container.bounds.contains(pointInContainer) else { return nil }
        return super.hitTest(point)
    }

    func focus() {
        layoutSubtreeIfNeeded()

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
        statusLabel.stringValue = status.text
        statusLabel.textColor = status.color
        needsLayout = true
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
        container.layer?.backgroundColor = TokyoNight.panelElevated.withAlphaComponent(0.74).cgColor
        container.layer?.borderColor = TokyoNight.blue.withAlphaComponent(0.24).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 14
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.22
        container.layer?.shadowRadius = 18
        container.layer?.shadowOffset = NSSize(width: 0, height: -6)
    }

    private func configureLabels() {
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        iconView.contentTintColor = TokyoNight.cyan.withAlphaComponent(0.92)

        promptLabel.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        promptLabel.textColor = TokyoNight.muted

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = TokyoNight.muted.withAlphaComponent(0.95)
        statusLabel.alignment = .right
    }

    private func configureTextField(query: String) {
        textField.stringValue = query
        textField.font = .systemFont(ofSize: 15, weight: .medium)
        textField.textColor = TokyoNight.foreground
        textField.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [
                .foregroundColor: TokyoNight.muted,
                .font: NSFont.systemFont(ofSize: 15, weight: .regular)
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

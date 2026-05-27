@preconcurrency import AppKit
import PDFKit

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
}

@MainActor
final class PDFSearchController {
    enum Direction {
        case next
        case previous
    }

    private weak var pdfView: VellumPDFView?
    private var overlay: SearchCommandOverlayView?
    private var query = ""
    private var matches: [PDFSelection] = []
    private var selectedIndex: Int?
    private var committedQuery = ""
    private var committedMatches: [PDFSelection] = []
    private var committedSelectedIndex: Int?

    init(pdfView: VellumPDFView) {
        self.pdfView = pdfView
    }

    func begin() {
        guard let pdfView, pdfView.document != nil else { return }

        pdfView.stopScrollAnimation()
        pdfView.hideAIExplanationPopover()
        query = committedQuery
        matches = committedMatches
        selectedIndex = committedSelectedIndex

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
        guard !matches.isEmpty else { return }

        let current = selectedIndex ?? 0
        switch direction {
        case .next:
            selectedIndex = (current + 1) % matches.count
        case .previous:
            selectedIndex = (current + matches.count - 1) % matches.count
        }

        updateOverlayStatus()
        jumpToSelectedMatch(recordJump: true)
        commitCurrentSearchState()
    }

    private func update(query nextQuery: String, resetSelection: Bool) {
        query = nextQuery

        guard let pdfView, let document = pdfView.document else {
            matches = []
            selectedIndex = nil
            updateOverlayStatus()
            return
        }

        let term = nextQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            matches = []
            selectedIndex = nil
            pdfView.highlightedSelections = []
            updateOverlayStatus()
            return
        }

        matches = document.findString(
            term,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )
        pdfView.highlightedSelections = matches

        if matches.isEmpty {
            selectedIndex = nil
        } else if resetSelection {
            selectedIndex = firstMatchIndexAtOrAfterVisiblePage(in: document)
        } else if let selectedIndex {
            self.selectedIndex = min(selectedIndex, matches.count - 1)
        } else {
            selectedIndex = 0
        }

        updateOverlayStatus()
    }

    private func commit() {
        guard !matches.isEmpty else {
            updateOverlayStatus()
            return
        }

        dismissOverlay(returnFocus: true)
        jumpToSelectedMatch(recordJump: true)
        commitCurrentSearchState()
    }

    private func cancel() {
        restoreCommittedSearchState()
        dismissOverlay(returnFocus: true)
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
              let selectedIndex,
              matches.indices.contains(selectedIndex) else { return }

        let selection = matches[selectedIndex]

        pdfView.cancelPendingRestore()
        if recordJump {
            pdfView.recordJumpSource()
        }
        pdfView.stopScrollAnimation()
        pdfView.stopZoomState()
        pdfView.textSelectionNavigationState = nil
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)

        DispatchQueue.main.async { [weak pdfView, weak selection] in
            guard let pdfView, let selection else { return }
            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.go(to: selection)
        }
    }

    private func firstMatchIndexAtOrAfterVisiblePage(in document: PDFDocument) -> Int {
        let visiblePageIndex = currentVisiblePageIndex(in: document)
        return matches.firstIndex { selection in
            firstPageIndex(for: selection, in: document).map { $0 >= visiblePageIndex } == true
        } ?? 0
    }

    private func firstPageIndex(for selection: PDFSelection, in document: PDFDocument) -> Int? {
        selection.pages
            .map { document.index(for: $0) }
            .filter { $0 != NSNotFound }
            .min()
    }

    private func currentVisiblePageIndex(in document: PDFDocument) -> Int {
        guard let pdfView else { return 0 }

        if let snapshot = pdfView.snapshot() {
            return min(max(snapshot.pageIndex, 0), document.pageCount - 1)
        }

        if let page = pdfView.currentPage {
            let index = document.index(for: page)
            if index != NSNotFound {
                return min(max(index, 0), document.pageCount - 1)
            }
        }

        return 0
    }

    private func updateOverlayStatus() {
        let status: SearchCommandOverlayView.Status
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .hint("Type to search")
        } else if matches.isEmpty {
            status = .error("No matches")
        } else {
            status = .count(current: (selectedIndex ?? 0) + 1, total: matches.count)
        }

        overlay?.update(status: status)
    }

    private func commitCurrentSearchState() {
        committedQuery = query
        committedMatches = matches
        committedSelectedIndex = selectedIndex
    }

    private func restoreCommittedSearchState() {
        query = committedQuery
        matches = committedMatches
        selectedIndex = committedSelectedIndex
        pdfView?.highlightedSelections = committedMatches
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

    private let container = NSView()
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

        let width = min(max(bounds.width * 0.52, 420), 720)
        let height: CGFloat = 52
        container.frame = NSRect(
            x: bounds.midX - width / 2,
            y: bounds.minY + 22,
            width: width,
            height: height
        )

        promptLabel.frame = NSRect(x: 18, y: 13, width: 18, height: 26)
        statusLabel.sizeToFit()
        let statusWidth = min(max(statusLabel.frame.width, 74), 140)
        statusLabel.frame = NSRect(
            x: container.bounds.maxX - statusWidth - 18,
            y: 15,
            width: statusWidth,
            height: 22
        )
        textField.frame = NSRect(
            x: promptLabel.frame.maxX + 8,
            y: 14,
            width: max(80, statusLabel.frame.minX - promptLabel.frame.maxX - 20),
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
        container.wantsLayer = true
        container.layer?.backgroundColor = TokyoNight.backgroundDeep.withAlphaComponent(0.96).cgColor
        container.layer?.borderColor = TokyoNight.border.withAlphaComponent(0.82).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 12
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.25
        container.layer?.shadowRadius = 16
        container.layer?.shadowOffset = NSSize(width: 0, height: -3)
    }

    private func configureLabels() {
        promptLabel.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        promptLabel.textColor = TokyoNight.blue

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = TokyoNight.muted
        statusLabel.alignment = .right
    }

    private func configureTextField(query: String) {
        textField.stringValue = query
        textField.font = .systemFont(ofSize: 16, weight: .medium)
        textField.textColor = TokyoNight.foreground
        textField.placeholderAttributedString = NSAttributedString(
            string: "Search in document",
            attributes: [
                .foregroundColor: TokyoNight.muted,
                .font: NSFont.systemFont(ofSize: 16, weight: .regular)
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

@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF search geometry")
struct PDFSearchGeometryTests {
    @Test @MainActor
    func committedSearchRecordsPositionBeforePreview() async throws {
        let (window, view) = try makeReader(pageCount: 3, wordPage: 2)
        defer { view.searchController?.clear(); window.close() }
        let original = try #require(view.snapshot())
        view.beginSearchCommand()
        let controller = try #require(view.searchController)
        let field = try #require(searchField(in: view))
        enter("alpha", into: field)
        try await waitUntil(in: view) {
            guard controller.hasVisibleHighlights,
                  let selection = controller.activeSearchSelection,
                  let page = selection.pages.first,
                  page === view.document?.page(at: 2) else { return false }
            return view.convert(selection.bounds(for: page), from: page).intersects(view.bounds)
        }
        #expect(view.jumpBackStack.isEmpty)

        _ = field.delegate?.control?(
            field,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        let source = try #require(view.jumpBackStack.last)
        #expect(source.pageIndex == original.pageIndex)
        #expect(source.pointOnPage == original.pointOnPage)
        #expect(source.scrollOrigin == original.scrollOrigin)
    }

    @Test @MainActor
    func scrollingMaterializesEveryVisiblePageWithoutChangingActiveMatch() async throws {
        let (window, view) = try makeReader(pageCount: 6, wordPage: nil, pageSize: NSSize(width: 400, height: 400))
        defer { view.searchController?.clear(); window.close() }
        view.scaleFactor = 0.4
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        view.beginSearchCommand()
        let controller = try #require(view.searchController)
        enter("alpha", into: try #require(searchField(in: view)))
        try await waitUntil(in: view) { (view.highlightedSelections?.count ?? 0) >= 3 }
        let activePage = try #require(controller.activeSearchSelection?.pages.first)
        let visibleBefore = Set(view.visiblePages.map(ObjectIdentifier.init))
        #expect(visibleBefore.count > 2)
        #expect(visibleBefore.isSubset(of: highlightedPages(in: view)))

        view.scrollToDocumentEdge(.bottom)
        try await waitUntil(in: view) {
            let visible = Set(view.visiblePages.map(ObjectIdentifier.init))
            return visible != visibleBefore && visible.isSubset(of: highlightedPages(in: view))
        }
        #expect(controller.activeSearchSelection?.pages.first === activePage)
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func selectionLinesUseDisplayedCharacterBounds(rotation: Int) throws {
        let (window, view) = try makeReader(pageCount: 1, wordPage: 0)
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        page.setBounds(NSRect(x: 20, y: 30, width: 500, height: 700), for: .cropBox)
        page.rotation = rotation
        let lines = view.textLines(onPageAt: 0, pageStarts: [0, page.numberOfCharacters])
        let characters = lines.flatMap(\.characters)
        let geometry = PDFPageDisplayGeometry(page: page, box: view.displayBox)
        #expect(!characters.isEmpty)
        for character in characters {
            let bounds = geometry.rect(forPageRect: page.characterBounds(at: character.globalOffset))
            #expect(character.minX == bounds.minX)
            #expect(character.centerX == bounds.midX)
            #expect(character.centerY == bounds.midY)
        }
    }

    @Test @MainActor
    func rotatedSearchMovesInDisplayedReadingOrder() async throws {
        let (window, view) = try makeReader(pageCount: 1, wordPage: 0, multipleMatches: true)
        defer { view.searchController?.clear(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        page.rotation = 180
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        view.beginSearchCommand()
        let controller = try #require(view.searchController)
        enter("alpha", into: try #require(searchField(in: view)))
        try await waitUntil(in: view) { (view.highlightedSelections?.count ?? 0) == 3 }

        let firstY = try #require(controller.activeSearchSelection).bounds(for: page).midY
        view.vimSearchNext()
        let secondY = try #require(controller.activeSearchSelection).bounds(for: page).midY
        view.vimSearchNext()
        let thirdY = try #require(controller.activeSearchSelection).bounds(for: page).midY
        #expect(firstY < secondY)
        #expect(secondY < thirdY)
    }

    @Test @MainActor
    func rotatedSelectionCaretsUseLogicalCharacterEdges() throws {
        let (window, view) = try makeReader(pageCount: 1, wordPage: 0)
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        page.rotation = 180
        let range = (try #require(page.string) as NSString).range(of: "alpha")
        let pageStarts = [0, page.numberOfCharacters]
        let start = try #require(view.textCaret(atInsertionOffset: range.location, preferTrailingEdge: false, pageStarts: pageStarts))
        let end = try #require(view.textCaret(atInsertionOffset: range.location + range.length, preferTrailingEdge: true, pageStarts: pageStarts))
        #expect(start.point.x > end.point.x)
        #expect(start.slotIndex > end.slotIndex)
    }

    @MainActor
    private func makeReader(
        pageCount: Int,
        wordPage: Int?,
        pageSize: NSSize = NSSize(width: 612, height: 792),
        multipleMatches: Bool = false
    ) throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for index in 0..<pageCount {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ((wordPage == nil || wordPage == index ? "alpha" : "other") as NSString).draw(
                at: NSPoint(x: 72, y: pageSize.height - 100),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
            )
            if multipleMatches {
                for y: CGFloat in [300, 100] {
                    ("alpha" as NSString).draw(at: NSPoint(x: 72, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data as Data)
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        return (window, view)
    }

    @MainActor
    private func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { searchField(in: $0) }.first
    }

    @MainActor
    private func enter(_ query: String, into field: NSTextField) {
        field.stringValue = query
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    @MainActor
    private func highlightedPages(in view: VellumPDFView) -> Set<ObjectIdentifier> {
        Set((view.highlightedSelections ?? []).flatMap(\.pages).map(ObjectIdentifier.init))
    }

    @MainActor
    private func waitUntil(in view: VellumPDFView, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "current page: \(view.currentPage.flatMap { view.document?.index(for: $0) } ?? -1); visible pages: \(view.visiblePages.map { view.document?.index(for: $0) ?? -1 }); highlighted: \(view.highlightedSelections?.count ?? 0); has target: \(view.searchController?.hasTextTarget ?? false)")
    }
}

@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@Suite("Search command")
struct SearchCommandTests {
    @Test
    @MainActor
    func escapeKeepsProgressiveResultsHiddenUntilNextSearchMove() async throws {
        _ = NSApplication.shared
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ("alpha" as NSString).draw(
                at: NSPoint(x: 72, y: 720),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        let document = try #require(PDFDocument(data: data as Data))
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.document = document
        view.beginSearchCommand()
        let controller = try #require(view.searchController)
        defer { controller.clear() }

        var escaped = false
        // Escape at the first partial publication, before the next page can be scanned.
        let observation = view.observe(\.highlightedSelections, options: [.new]) { _, change in
            let highlightedCount = change.newValue.flatMap { $0 }?.count
            MainActor.assumeIsolated {
                guard !escaped, controller.hasVisibleHighlights else { return }
                escaped = true
                #expect(highlightedCount == 1)
                #expect(controller.handleEscape())
                #expect(!controller.hasVisibleHighlights)
            }
        }
        defer { observation.invalidate() }

        func textFields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
        }
        let field = try #require(textFields(in: view).first { $0.isEditable })
        field.stringValue = "alpha"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !escaped && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(escaped)
        for _ in 0..<10 { await Task.yield() }
        #expect(!controller.hasVisibleHighlights)
        #expect(view.highlightedSelections?.isEmpty == true)

        view.vimSearchNext()
        #expect(controller.hasVisibleHighlights)
        #expect(controller.activeSearchSelection?.pages.first === document.page(at: 1))
    }

    @Test
    func resultNavigatorChoosesLaterResultOnSamePage() {
        let locations = [
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 760, width: 60, height: 16),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 500, width: 60, height: 16),
                documentOrder: 1
            ),
            SearchResultLocation(
                pageIndex: 3,
                boundsInPage: NSRect(x: 20, y: 780, width: 60, height: 16),
                documentOrder: 2
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 2, pointInPage: NSPoint(x: 0, y: 620)),
            in: locations
        )

        #expect(index == 1)
    }

    @Test
    func resultNavigatorFallsThroughToLaterPage() {
        let locations = [
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 760, width: 60, height: 16),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 3,
                boundsInPage: NSRect(x: 20, y: 780, width: 60, height: 16),
                documentOrder: 1
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 2, pointInPage: NSPoint(x: 0, y: 100)),
            in: locations
        )

        #expect(index == 1)
    }

    @Test
    func resultNavigatorUsesXPositionOnSameLine() {
        let locations = [
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 40, y: 300, width: 40, height: 18),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 160, y: 300, width: 40, height: 18),
                documentOrder: 1
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 1, pointInPage: NSPoint(x: 100, y: 309)),
            in: locations
        )

        #expect(index == 1)
    }

    @Test
    func resultNavigatorKeepsMatchWhenAnchorIsAtMatchStart() {
        let locations = [
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 40, y: 300, width: 40, height: 18),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 160, y: 300, width: 40, height: 18),
                documentOrder: 1
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 1, pointInPage: NSPoint(x: 40, y: 300)),
            in: locations
        )

        #expect(index == 0)
    }

    @Test
    func resultNavigatorChoosesPreviousResultFromAnchor() {
        let locations = [
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 40, y: 760, width: 40, height: 18),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 40, y: 300, width: 40, height: 18),
                documentOrder: 1
            ),
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 40, y: 760, width: 40, height: 18),
                documentOrder: 2
            )
        ]

        let index = SearchResultNavigator.lastIndex(
            beforeOrAt: SearchAnchor(pageIndex: 1, pointInPage: NSPoint(x: 0, y: 620)),
            in: locations
        )

        #expect(index == 0)
    }

    @Test
    func anchoredMoveAdvancesWhenAnchorResolvesToCurrentNextResult() {
        let index = SearchResultNavigator.resolvedAnchoredMoveIndex(
            anchoredIndex: 2,
            activeIndex: 2,
            resultCount: 5,
            direction: .next
        )

        #expect(index == 3)
    }

    @Test
    func anchoredMoveAdvancesWhenAnchorResolvesToCurrentPreviousResult() {
        let index = SearchResultNavigator.resolvedAnchoredMoveIndex(
            anchoredIndex: 2,
            activeIndex: 2,
            resultCount: 5,
            direction: .previous
        )

        #expect(index == 1)
    }

    @Test
    func anchoredMoveUsesRecomputedAnchorWhenItChanged() {
        let index = SearchResultNavigator.resolvedAnchoredMoveIndex(
            anchoredIndex: 4,
            activeIndex: 2,
            resultCount: 5,
            direction: .next
        )

        #expect(index == 4)
    }

    @Test
    func resultLocationsSortByPageReadingPositionAndX() {
        let locations = [
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 700, width: 40, height: 18),
                documentOrder: 3
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 140, y: 500, width: 40, height: 18),
                documentOrder: 2
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 40, y: 500, width: 40, height: 18),
                documentOrder: 1
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 20, y: 760, width: 40, height: 18),
                documentOrder: 0
            )
        ]

        let sorted = locations.sorted(by: SearchResultLocation.documentOrderSort)

        #expect(sorted.map(\.documentOrder) == [0, 1, 2, 3])
    }

    @Test
    func textFinderMatchesCaseAndDiacriticsInsensitively() {
        let matches = SearchTextFinder.matches(
            in: "Cafe CAFÉ cafe",
            term: "café",
            pageIndex: 4,
            startingDocumentOrder: 7
        )

        #expect(matches.map(\.pageIndex) == [4, 4, 4])
        #expect(matches.map(\.documentOrder) == [7, 8, 9])
        #expect(matches.map(\.range.location) == [0, 5, 10])
    }

    @Test
    func textFinderFindsMultipleMatchesOnOnePage() {
        let matches = SearchTextFinder.matches(
            in: "alpha beta alpha alpha",
            term: "alpha",
            pageIndex: 2,
            startingDocumentOrder: 3
        )

        #expect(matches.map(\.range.location) == [0, 11, 17])
        #expect(matches.map(\.range.length) == [5, 5, 5])
        #expect(matches.map(\.documentOrder) == [3, 4, 5])
    }

    @Test
    func textFinderRejectsEmptyInputs() {
        #expect(
            SearchTextFinder.matches(
                in: "",
                term: "needle",
                pageIndex: 0,
                startingDocumentOrder: 0
            ).isEmpty
        )
        #expect(
            SearchTextFinder.matches(
                in: "haystack",
                term: "",
                pageIndex: 0,
                startingDocumentOrder: 0
            ).isEmpty
        )
    }

    @Test
    func previewSearchScansForwardFromCurrentPageBeforeWrapping() {
        #expect(PDFSearchController.previewPageScanOrder(pageCount: 5, anchorPageIndex: 2) == [2, 3, 4, 0, 1])
        #expect(PDFSearchController.previewPageScanOrder(pageCount: 5, anchorPageIndex: -3) == [0, 1, 2, 3, 4])
        #expect(PDFSearchController.previewPageScanOrder(pageCount: 5, anchorPageIndex: 12) == [4, 0, 1, 2, 3])
        #expect(PDFSearchController.previewPageScanOrder(pageCount: 0, anchorPageIndex: 2) == [])
    }

    @Test
    func activePreviewMatchIsPreservedWhenFullResultsArePublished() {
        let activeMatch = SearchTextMatch(
            pageIndex: 2,
            range: NSRange(location: 40, length: 3),
            documentOrder: 0
        )
        let results = [
            PDFSearchResult(
                match: SearchTextMatch(pageIndex: 0, range: NSRange(location: 12, length: 3), documentOrder: 0),
                selection: nil,
                location: nil
            ),
            PDFSearchResult(
                match: SearchTextMatch(pageIndex: 2, range: NSRange(location: 40, length: 3), documentOrder: 4),
                selection: nil,
                location: nil
            ),
            PDFSearchResult(
                match: SearchTextMatch(pageIndex: 2, range: NSRange(location: 90, length: 3), documentOrder: 5),
                selection: nil,
                location: nil
            )
        ]

        #expect(PDFSearchController.index(of: activeMatch, in: results) == 1)
    }

    @Test
    func readingAnchorUsesVisualTopInFlippedViewport() {
        #expect(SearchReadingAnchor.pointY(visibleMinY: 100, visibleHeight: 900, isFlipped: true) == 100)
    }

    @Test
    func readingAnchorUsesVisualTopInNonFlippedViewport() {
        #expect(SearchReadingAnchor.pointY(visibleMinY: 100, visibleHeight: 900, isFlipped: false) == 1000)
    }

    @Test
    func fieldEditorCommandsMapEnterAndEscape() {
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.insertNewline(_:))
            ) == .commit
        )
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            ) == .commit
        )
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.cancelOperation(_:))
            ) == .cancel
        )
    }

    @Test
    func unrelatedFieldEditorCommandsAreIgnored() {
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.moveDown(_:))
            ) == nil
        )
    }
}

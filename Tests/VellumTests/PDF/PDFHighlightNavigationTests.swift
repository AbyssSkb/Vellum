@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF highlight navigation")
struct PDFHighlightNavigationTests {
    @Test(arguments: ["centered", "zoomedVisible", "zoomedOffscreen"], [false, true])
    func highlightJumpOnlyMovesHorizontallyForOffscreenTargets(scenario: String, textless: Bool) async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        if textless {
            let page = try #require(view.document?.page(at: 1))
            page.addAnnotation(PDFAnnotation(bounds: NSRect(x: 72, y: 300, width: 60, height: 20),
                                             forType: .highlight, withProperties: nil))
        } else {
            _ = try highlight("beta", on: 1, in: view)
        }
        view.scaleFactor = scenario == "centered" ? 1 : 2
        view.layoutDocumentView()
        await nextTestMainQueueTurn()
        let scrollView = try #require(view.pdfScrollView)
        let clip = scrollView.contentView
        if scenario != "centered" {
            clip.scroll(to: NSPoint(x: scenario == "zoomedOffscreen" ? 100 : 40, y: clip.bounds.origin.y))
        }
        let originX = clip.bounds.origin.x
        let item = try #require(view.highlightListItems().first)
        let annotation = try #require(item.annotations.first)
        let page = try #require(annotation.page)
        let targetBounds = textless
            ? annotation.bounds
            : try #require(page.selection(for: NSRange(location: 0, length: 4))).bounds(for: page)
        let documentView = try #require(scrollView.documentView)
        let target = view.convert(view.convert(targetBounds, from: page), to: documentView)
        #expect((target.minX >= clip.bounds.minX && target.maxX <= clip.bounds.maxX) == (scenario != "zoomedOffscreen"))

        view.vimSelectHighlight(item)
        await nextTestMainQueueTurn()

        #expect(view.currentSelection?.string == (textless ? nil : "beta"))
        #expect(target.minX >= clip.bounds.minX && target.maxX <= clip.bounds.maxX)
        if scenario != "zoomedOffscreen" {
            #expect(abs(clip.bounds.origin.x - originX) < 0.5,
                    "Highlight jump moved x from \(originX) to \(clip.bounds.origin.x), scenario=\(scenario)")
        }
    }

    @Test
    func multilineAndMultipageHighlightsProduceOneCompleteSearchableItem() throws {
        let document = try makeTextPDF(pages: [
            [("First highlighted line", NSPoint(x: 72, y: 650)), ("Second highlighted line", NSPoint(x: 72, y: 620))],
            [("Third highlighted line", NSPoint(x: 72, y: 650))]
        ])
        let view = VellumPDFView()
        view.document = document
        let selection = try #require(document.page(at: 0)?.selection(for: NSRect(x: 50, y: 600, width: 500, height: 100)))
        selection.add(try #require(document.page(at: 1)?.selection(for: NSRect(x: 50, y: 600, width: 500, height: 100))))
        let annotations = view.addHighlightAnnotations(for: selection, color: .yellow)
        try #require(annotations.count == 3)
        annotations.forEach { $0.contents = AIExplanationAnnotation.encode("An AI answer") }

        let items = view.highlightListItems()
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.annotations.count == 3)
        #expect(item.pageNumbers == [1, 2])
        #expect(item.text.contains("First highlighted line"))
        #expect(item.text.contains("Second highlighted line"))
        #expect(item.text.contains("Third highlighted line"))
        #expect(item.searchableText.contains("2"))
        #expect(!item.searchableText.contains("An AI answer"))
    }

    @Test
    func listUsesDocumentOrderAndIncludesOrdinaryAndAIHighlights() throws {
        let document = try makeTextPDF(pages: [
            [("alpha", NSPoint(x: 72, y: 650)), ("beta", NSPoint(x: 72, y: 300))],
            [("gamma", NSPoint(x: 72, y: 650))]
        ])
        let view = VellumPDFView()
        view.document = document
        let beta = try highlight("beta", on: 0, in: view)
        beta.contents = AIExplanationAnnotation.encode("Explanation")
        _ = try highlight("gamma", on: 1, in: view)
        _ = try highlight("alpha", on: 0, in: view)
        #expect(view.highlightListItems().map(\.text) == ["alpha", "beta", "gamma"])
    }

    @Test
    func legacyConnectedLinesRemainOneItem() throws {
        let document = try makeTextPDF(pages: [[
            ("first", NSPoint(x: 72, y: 650)), ("second", NSPoint(x: 72, y: 625))
        ]])
        let view = VellumPDFView()
        view.document = document
        let page = try #require(document.page(at: 0))
        for word in ["first", "second"] {
            let range = (try #require(page.string) as NSString).range(of: word)
            let selection = try #require(page.selection(for: range))
            let annotation = PDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
            annotation.color = .yellow
            page.addAnnotation(annotation)
        }
        let item = try #require(view.highlightListItems().first)
        #expect(view.highlightListItems().count == 1)
        #expect(item.annotations.count == 2)
        #expect(item.text.contains("first"))
        #expect(item.text.contains("second"))
    }

    @Test
    func navigationSelectsTextWrapsAndKeepsExistingActionsUsable() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        _ = try highlight("alpha", on: 0, in: view)
        _ = try highlight("beta", on: 1, in: view)
        let items = view.highlightListItems()
        view.vimSelectHighlight(items[0])
        #expect(view.currentSelection?.string == "alpha")
        #expect(window.firstResponder === view)
        #expect(view.hasNavigableTextSelection)

        view.vimNavigateHighlight(1)
        #expect(view.currentSelection?.string == "beta")
        view.vimNavigateHighlight(1)
        #expect(view.currentSelection?.string == "alpha")
        view.vimNavigateHighlight(-1)
        #expect(view.currentSelection?.string == "beta")
        #expect(view.vimDeleteHighlightsForSelection())
        #expect(view.highlightListItems().map(\.text) == ["alpha"])
    }

    @Test
    func openingAnItemRecordsTheOriginalReadingPosition() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        _ = try highlight("beta", on: 1, in: view)
        let original = try #require(view.snapshot())
        view.vimSelectHighlight(try #require(view.highlightListItems().first))
        #expect(view.jumpBackStack.last?.pageIndex == original.pageIndex)
        #expect(view.jumpBackStack.last?.pointOnPage == original.pointOnPage)
        await nextTestMainQueueTurn()
        view.vimJumpBack()
        try await waitForTestCondition("Highlight navigation returns to its source page") {
            view.snapshot()?.pageIndex == original.pageIndex
        }
    }

    @Test
    func consecutiveTextlessHighlightsAdvanceAndDiscardTheAnchorAfterOtherNavigation() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        let page = try #require(view.document?.page(at: 0))
        let annotations = [500.0, 300.0, 100.0].map { y in
            let annotation = PDFAnnotation(bounds: NSRect(x: 400, y: y, width: 100, height: 20),
                                           forType: .highlight, withProperties: nil)
            page.addAnnotation(annotation)
            return annotation
        }
        let items = view.highlightListItems()
        #expect(items.count == 3)
        view.vimSelectHighlight(items[0])
        #expect(view.currentSelection == nil)
        view.vimNavigateHighlight(1)
        #expect(view.highlightNavigationAnchor?.annotation === annotations[1])
        await nextTestMainQueueTurn()
        view.vimNavigateHighlight(1)
        #expect(view.highlightNavigationAnchor?.annotation === annotations[2])
        view.vimNavigateHighlight(1)
        #expect(view.highlightNavigationAnchor?.annotation === annotations[0])
        view.vimNavigateHighlight(-1)
        #expect(view.highlightNavigationAnchor?.annotation === annotations[2])

        let generation = view.restoreGeneration
        view.vimGoToFirstPage()
        #expect(view.restoreGeneration != generation)
        #expect(view.highlightNavigationAnchor?.generation != view.restoreGeneration)
    }

    @Test
    func differentHeightHighlightsHaveDeterministicTopToBottomOrdering() throws {
        let document = PDFDocument()
        let page = PDFPage()
        document.insert(page, at: 0)
        let view = VellumPDFView()
        view.document = document
        let annotations = [
            NSRect(x: 300, y: 500, width: 60, height: 100),
            NSRect(x: 100, y: 575, width: 60, height: 10),
            NSRect(x: 200, y: 560, width: 60, height: 20)
        ].map { bounds in
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            HighlightAnnotationMetadata.setGroupID(UUID().uuidString, for: annotation)
            return annotation
        }
        for annotation in annotations.reversed() { page.addAnnotation(annotation) }
        #expect(view.highlightListItems().compactMap { $0.annotations.first }.map(ObjectIdentifier.init)
            == annotations.map(ObjectIdentifier.init))
    }

    @Test(arguments: [false, true])
    func staleItemsCannotChangeTheCurrentSelection(replaceDocument: Bool) throws {
        let document = try makeTextPDF(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        let view = VellumPDFView()
        view.document = document
        let annotation = try highlight("alpha", on: 0, in: view)
        let item = try #require(view.highlightListItems().first)
        if replaceDocument {
            view.document = try makeTextPDF(pages: [[("beta", NSPoint(x: 72, y: 650))]])
        } else {
            annotation.page?.removeAnnotation(annotation)
        }
        let page = try #require(view.document?.page(at: 0))
        let text = try #require(page.string) as NSString
        let selection = try #require(page.selection(for: text.range(of: "beta")))
        view.setCurrentSelection(selection, animate: false)
        let generation = view.restoreGeneration
        view.vimSelectHighlight(item)
        #expect(view.currentSelection?.string == "beta")
        #expect(view.restoreGeneration == generation)
    }

    @Test
    func emptyAndImageOnlyDocumentsRemainBrowsable() throws {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)
        let view = VellumPDFView()
        view.document = document
        #expect(view.highlightListItems().isEmpty)
        let annotation = PDFAnnotation(bounds: NSRect(x: 70, y: 600, width: 100, height: 20), forType: .highlight, withProperties: nil)
        page.addAnnotation(annotation)
        let item = try #require(view.highlightListItems().first)
        #expect(item.text.isEmpty)
        #expect(item.pageNumbers == [1])
        annotation.shouldDisplay = false
        #expect(view.highlightListItems().isEmpty)
    }

    private func highlight(_ word: String, on pageIndex: Int, in view: VellumPDFView) throws -> PDFAnnotation {
        let page = try #require(view.document?.page(at: pageIndex))
        let range = (try #require(page.string) as NSString).range(of: word)
        let selection = try #require(page.selection(for: range))
        return try #require(view.addHighlightAnnotations(for: selection, color: .yellow).first)
    }

    private func makeReader() async throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let document = try makeTextPDF(pages: [
            [("alpha", NSPoint(x: 72, y: 650))], [("beta", NSPoint(x: 72, y: 650))]
        ])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        view.goToFirstPage(nil)
        view.scrollToDocumentEdge(.top)
        await nextTestMainQueueTurn()
        try await waitForTestCondition("The first page is ready for highlight navigation") {
            view.currentPage === document.page(at: 0)
        }
        return (window, view)
    }

    private func close(_ window: NSWindow, _ view: VellumPDFView) {
        view.cancelPendingRestore()
        view.stopScrollAnimation()
        view.stopZoomState()
        view.readingPositionReportWorkItem?.cancel()
        view.readerStateSaveWorkItem?.cancel()
        window.close()
    }
}

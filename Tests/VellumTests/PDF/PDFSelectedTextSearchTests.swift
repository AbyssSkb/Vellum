@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF selected text search")
struct PDFSelectedTextSearchTests {
    @Test
    func phraseSearchStartsAfterSelectionAndNextPreviousWrap() async throws {
        let phrase = "alpha (beta)"
        let document = try makeTextPDF(pages: [[
            ("\(phrase) earlier", NSPoint(x: 72, y: 720)),
            ("\(phrase) source", NSPoint(x: 72, y: 650)),
            ("\(phrase) next", NSPoint(x: 72, y: 580)),
            ("alpha beta is different", NSPoint(x: 72, y: 510))
        ]])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        let selections = try phraseSelections(phrase, on: page)
        try #require(selections.count == 3)
        view.setCurrentSelection(selections[1], animate: false)
        let source = try #require(view.snapshot())
        let clipboardChangeCount = NSPasteboard.general.changeCount

        view.vimSearchSelectedText()

        let controller = try #require(view.searchController)
        #expect(view.currentSelection == nil)
        #expect(view.textSelectionNavigationState == nil)
        #expect(!view.handleTextSelectionKey("j", eventType: .keyDown))
        #expect(window.firstResponder === view)
        try await waitForTestCondition("Selected phrase search commits directly") {
            !controller.isSearchPending && controller.hasVisibleHighlights
        }
        #expect(view.highlightedSelections?.count == 3)
        #expect(controller.activeSearchSelection?.bounds(for: page) == selections[2].bounds(for: page))
        #expect(window.firstResponder === view)
        #expect(NSPasteboard.general.changeCount == clipboardChangeCount)
        #expect(view.jumpBackStack.count == 1)
        #expect(view.jumpBackStack.last?.pageIndex == source.pageIndex)
        #expect(view.jumpBackStack.last?.pointOnPage == source.pointOnPage)
        #expect(view.jumpBackStack.last?.scrollOrigin == source.scrollOrigin)

        view.vimSearchNext()
        #expect(controller.activeSearchSelection?.bounds(for: page) == selections[0].bounds(for: page))
        view.vimSearchPrevious()
        #expect(controller.activeSearchSelection?.bounds(for: page) == selections[2].bounds(for: page))
        view.vimSearchPrevious()
        #expect(controller.activeSearchSelection?.bounds(for: page) == selections[1].bounds(for: page))
    }

    @Test
    func missingSelectionExplainsTheReasonWithoutReplacingSearch() async throws {
        let document = try makeTextPDF(pages: [[("alpha alpha", NSPoint(x: 72, y: 650))]])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }

        view.vimSearchSelectedText()

        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noTextToSearch))
        #expect(view.searchController == nil)
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try #require(phraseSelections("alpha", on: page).first), animate: false)
        view.vimSearchSelectedText()
        let controller = try #require(view.searchController)
        try await waitForTestCondition("Search is available before a missing-selection command") {
            !controller.isSearchPending && controller.hasVisibleHighlights
        }
        let target = controller.activeSearchSelection

        view.vimSearchSelectedText()

        #expect(controller.activeSearchSelection === target)
        #expect(controller.hasVisibleHighlights)
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noTextToSearch))
        #expect(window.firstResponder === view)
    }

    @Test
    func replacingPendingSelectionSearchDiscardsOldQueryAndMoves() async throws {
        let document = try makeTextPDF(pages: [
            [("alpha gamma", NSPoint(x: 72, y: 650))],
            [("gamma", NSPoint(x: 72, y: 650))],
            [("alpha", NSPoint(x: 72, y: 650))]
        ])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try #require(phraseSelections("alpha", on: page).first), animate: false)
        view.vimSearchSelectedText()
        view.vimSearchNext()

        view.setCurrentSelection(try #require(phraseSelections("gamma", on: page).first), animate: false)
        view.vimSearchSelectedText()

        let controller = try #require(view.searchController)
        try await waitForTestCondition("Replacement selection search commits its own next match") {
            !controller.isSearchPending && controller.activeSearchSelection?.string == "gamma"
        }
        #expect(controller.activeSearchSelection?.pages.first === document.page(at: 1))
        #expect(view.jumpBackStack.count == 1)
        #expect(window.firstResponder === view)
    }

    @Test
    func pendingNextUsesTheCompleteResultListAndEscapeCancelsSearch() async throws {
        let document = try makeTextPDF(pages: (0..<3).map { _ in
            [("alpha", NSPoint(x: 72, y: 650))]
        })
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        let selection = try #require(phraseSelections("alpha", on: page).first)
        view.setCurrentSelection(selection, animate: false)
        view.vimSearchSelectedText()
        view.vimSearchNext()
        let controller = try #require(view.searchController)
        try await waitForTestCondition("Pending next follows the initial next occurrence") {
            !controller.isSearchPending && controller.activeSearchSelection?.pages.first === document.page(at: 2)
        }
        #expect(view.jumpBackStack.count == 1)

        view.setCurrentSelection(selection, animate: false)
        view.vimSearchSelectedText()
        #expect(controller.handleEscape())
        await nextTestMainQueueTurn()

        #expect(!controller.isSearchPending)
        #expect(!controller.hasTextTarget)
        #expect(!controller.hasVisibleHighlights)
        #expect(view.highlightedSelections?.isEmpty != false)
        #expect(window.firstResponder === view)
    }

    @Test
    func unmatchedCrossPageSelectionKeepsReaderFocus() async throws {
        let document = try makeTextPDF(pages: [
            [("alpha", NSPoint(x: 72, y: 650))],
            [("beta", NSPoint(x: 72, y: 650))]
        ])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: 1))
        let selection = try #require(phraseSelections("alpha", on: firstPage).first)
        selection.add(try #require(phraseSelections("beta", on: lastPage).first))
        view.setCurrentSelection(selection, animate: false)

        view.vimSearchSelectedText()

        let controller = try #require(view.searchController)
        try await waitForTestCondition("Cross-page phrase completes without a page-local match") {
            !controller.isSearchPending
        }
        #expect(!controller.hasTextTarget)
        #expect(!controller.hasVisibleHighlights)
        #expect(view.currentSelection == nil)
        #expect(window.firstResponder === view)
        #expect(view.jumpBackStack.isEmpty)
        #expect(!view.handleTextSelectionKey("j", eventType: .keyDown))
    }

    private func phraseSelections(_ phrase: String, on page: PDFPage) throws -> [PDFSelection] {
        let text = try #require(page.string)
        return try SearchTextFinder.matches(in: text, term: phrase, pageIndex: 0, startingDocumentOrder: 0).map {
            try #require(page.selection(for: $0.range))
        }
    }

    private func currentToast(in window: NSWindow) -> ToastView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
    }

    private func makeReader(document: PDFDocument) async throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        await nextTestMainQueueTurn()
        try #require(window.makeFirstResponder(view))
        return (window, view)
    }

    private func close(_ window: NSWindow, _ view: VellumPDFView) {
        view.searchController?.clear()
        view.cancelPendingRestore()
        view.stopScrollAnimation()
        view.stopZoomState()
        view.readingPositionReportWorkItem?.cancel()
        view.readerStateSaveWorkItem?.cancel()
        window.contentView = nil
        window.close()
    }
}

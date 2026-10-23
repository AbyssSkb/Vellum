@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF selection restore")
struct PDFSelectionRestoreTests {
    @Test(arguments: ["escape", "highlight", "delete", "search"])
    func restoreKeepsAdjustedRangeAndSwappedEndpoint(after action: String) async throws {
        let document = try makeTextPDF(pages: [[("first second third fourth", NSPoint(x: 72, y: 650))]])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try selection("second", on: page), animate: false)
        #expect(view.vimSwapTextSelectionEndpoint())
        #expect(view.vimNavigateTextSelection("h"))
        let selected = try #require(view.currentSelection?.string)
        let state = try #require(view.textSelectionNavigationState)
        let ranges = selectionRanges(try #require(view.currentSelection), in: document)

        switch action {
        case "escape":
            #expect(view.handleTextSelectionKey("\u{1b}", eventType: .keyDown))
        case "highlight":
            view.vimHighlightSelection(color: .systemCyan)
        case "delete":
            _ = view.addHighlightAnnotations(for: try #require(view.currentSelection), color: .systemCyan)
            #expect(view.vimDeleteHighlightsForSelection())
        case "search":
            view.vimSearchSelectedText()
        default:
            Issue.record("Unexpected clearing action")
        }
        try #require(view.currentSelection == nil)

        view.vimRestoreTextSelection()

        #expect(view.currentSelection?.string == selected)
        #expect(selectionRanges(try #require(view.currentSelection), in: document) == ranges)
        #expect(view.textSelectionNavigationState?.anchorOffset == state.anchorOffset)
        #expect(view.textSelectionNavigationState?.extentOffset == state.extentOffset)
        #expect(view.textSelectionNavigationState?.anchorCaret?.point == state.anchorCaret?.point)
        #expect(view.textSelectionNavigationState?.extentCaret?.point == state.extentCaret?.point)
        #expect(window.firstResponder === view)
        #expect(view.vimNavigateTextSelection("h"))
        #expect(view.textSelectionNavigationState?.anchorOffset == state.anchorOffset)
        #expect(view.textSelectionNavigationState?.extentOffset == state.extentOffset - 1)
    }

    @Test
    func plainSelectionRestoresAfterEscapeWithoutAnyPriorMotion() async throws {
        let document = try makeTextPDF(pages: [[("first second third", NSPoint(x: 72, y: 650))]])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try selection("second", on: page), animate: false)
        #expect(view.handleTextSelectionKey("\u{1b}", eventType: .keyDown))

        view.vimRestoreTextSelection()

        #expect(view.currentSelection?.string == "second")
        #expect(view.handleTextSelectionKey("l", eventType: .keyDown))
        #expect(view.currentSelection?.string == "second ")
    }

    @Test
    func copiedSelectionPreservesDiscontiguousRangesAcrossPages() async throws {
        let document = try makeTextPDF(pages: [
            [("first second third fourth", NSPoint(x: 72, y: 650))],
            [("fifth sixth seventh", NSPoint(x: 72, y: 650))]
        ])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: 1))
        let original = try selection("second", on: firstPage)
        original.add(try selection("fourth", on: firstPage))
        original.add(try selection("sixth", on: lastPage))
        view.setCurrentSelection(original, animate: false)
        let expected = selectionRanges(try #require(view.currentSelection), in: document)
        let originalText = view.currentSelection?.string
        view.clearTextSelectionForVimNavigation()

        view.vimRestoreTextSelection()

        let restored = try #require(view.currentSelection)
        #expect(restored.pages.count == 2)
        #expect(restored.string == originalText)
        #expect(selectionRanges(restored, in: document) == expected)
    }

    @Test
    func restoreCancelsPendingSearchAndRetainsTheSourceSelection() async throws {
        let document = try makeTextPDF(pages: (0..<3).map { _ in
            [("first second third", NSPoint(x: 72, y: 650))]
        })
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try selection("second", on: page), animate: false)
        view.vimSearchSelectedText()
        let search = try #require(view.searchController)

        view.vimRestoreTextSelection()
        await nextTestMainQueueTurn()

        #expect(view.currentSelection?.string == "second")
        #expect(view.currentSelection?.pages.first === page)
        #expect(!search.isSearchPending)
        #expect(!search.hasVisibleHighlights)
        #expect(view.highlightedSelections?.isEmpty != false)
        #expect(window.firstResponder === view)
    }

    @Test
    func documentReplacementCannotRestoreAStaleSelection() async throws {
        let document = try makeTextPDF(pages: [[("first second", NSPoint(x: 72, y: 650))]])
        let replacement = try makeTextPDF(pages: [[("other document", NSPoint(x: 72, y: 650))]])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        view.setCurrentSelection(try selection("second", on: #require(document.page(at: 0))), animate: false)
        view.clearTextSelectionForVimNavigation()
        view.document = replacement

        view.vimRestoreTextSelection()

        #expect(view.currentSelection == nil)
        #expect(view.savedTextSelection == nil)
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noPreviousTextSelection))
    }

    @Test
    func selectedPagesMovedToAnotherDocumentCannotBeRestored() async throws {
        let document = try makeTextPDF(pages: [
            [("first second", NSPoint(x: 72, y: 650))],
            [("remaining page", NSPoint(x: 72, y: 650))]
        ])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try selection("second", on: page), animate: false)
        view.clearTextSelectionForVimNavigation()
        document.removePage(at: 0)
        let replacement = PDFDocument()
        replacement.insert(page, at: 0)

        view.vimRestoreTextSelection()

        #expect(view.currentSelection == nil)
        #expect(view.savedTextSelection == nil)
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noPreviousTextSelection))
    }

    @Test
    func restoreRevealsTheEndpointWithoutMovingCenteredPagesSideways() async throws {
        let lines = (0..<24).map { index in
            ("line \(index) selectable text", NSPoint(x: 72, y: 720 - index * 24))
        }
        let document = try makeTextPDF(pages: [lines])
        let (window, view) = try await makeReader(document: document, width: 900, height: 240)
        defer { close(window, view) }
        view.scaleFactor = 0.8
        view.layoutDocumentView()
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(try selection("line 22", on: page), animate: false)
        view.clearTextSelectionForVimNavigation()
        view.scrollToDocumentEdge(.top)
        await nextTestMainQueueTurn()
        let clip = try #require(view.pdfScrollView).contentView
        let origin = clip.bounds.origin

        view.vimRestoreTextSelection()

        #expect(view.currentSelection?.string == "line 22")
        #expect(abs(clip.bounds.origin.x - origin.x) < 0.5)
        #expect(abs(clip.bounds.origin.y - origin.y) > 1)
    }

    @Test
    func missingPreviousSelectionExplainsTheReason() async throws {
        let document = try makeTextPDF(pages: [[("first second", NSPoint(x: 72, y: 650))]])
        let (window, view) = try await makeReader(document: document)
        defer { close(window, view) }

        view.vimRestoreTextSelection()

        #expect(view.currentSelection == nil)
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noPreviousTextSelection))
        #expect(window.firstResponder === view)
    }

    private func selection(_ phrase: String, on page: PDFPage) throws -> PDFSelection {
        let text = try #require(page.string as NSString?)
        let range = text.range(of: phrase)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range))
    }

    private func selectionRanges(_ selection: PDFSelection, in document: PDFDocument) -> [[NSRange]] {
        (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { return [] }
            return (0..<selection.numberOfTextRanges(on: page)).map { selection.range(at: $0, on: page) }
        }
    }

    private func currentToast(in window: NSWindow) -> ToastView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
    }

    private func makeReader(document: PDFDocument, width: CGFloat = 800, height: CGFloat = 600) async throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF selection endpoint swap")
struct PDFSelectionEndpointSwapTests {
    @Test
    func noSelectionDoesNotCreateNavigationState() throws {
        let document = try makeDocument()
        let view = VellumPDFView(frame: .zero)
        view.document = document

        #expect(!view.vimSwapTextSelectionEndpoint())
        #expect(view.currentSelection == nil)
        #expect(view.textSelectionNavigationState == nil)
    }

    @Test
    func swappingTwicePreservesSelectionAndRestoresBothCarets() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: NSRange(location: 6, length: 6)), animate: false)
        #expect(view.vimNavigateTextSelection("j"))
        let selection = try #require(view.currentSelection)
        let original = try #require(view.textSelectionNavigationState)
        try #require(original.preferredX != nil)

        #expect(view.vimSwapTextSelectionEndpoint())

        let swapped = try #require(view.textSelectionNavigationState)
        #expect(view.currentSelection === selection)
        #expect(swapped.anchorOffset == original.extentOffset)
        #expect(swapped.extentOffset == original.anchorOffset)
        #expect(view.sameVisualCaret(swapped.anchorCaret, original.extentCaret))
        #expect(view.sameVisualCaret(swapped.extentCaret, original.anchorCaret))
        #expect(swapped.preferredX == nil)

        #expect(view.vimSwapTextSelectionEndpoint())

        let restored = try #require(view.textSelectionNavigationState)
        #expect(view.currentSelection === selection)
        #expect(restored.anchorOffset == original.anchorOffset)
        #expect(restored.extentOffset == original.extentOffset)
        #expect(view.sameVisualCaret(restored.anchorCaret, original.anchorCaret))
        #expect(view.sameVisualCaret(restored.extentCaret, original.extentCaret))
    }

    @Test(arguments: [("h", 5), ("l", 7), ("b", 0), ("w", 13), ("e", 13)])
    func followingMotionAdjustsTheFormerAnchor(motion: (String, Int)) throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: NSRange(location: 6, length: 6)), animate: false)

        #expect(view.vimSwapTextSelectionEndpoint())
        #expect(view.currentSelection?.string == "second")
        #expect(view.vimNavigateTextSelection(motion.0))

        #expect(view.textSelectionNavigationState?.anchorOffset == 12)
        #expect(view.textSelectionNavigationState?.extentOffset == motion.1)
    }

    @Test
    func existingReversedSelectionKeepsItsDirectionUntilSwapped() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: NSRange(location: 6, length: 6)), animate: false)
        #expect(view.vimNavigateTextSelection("h", count: 7))
        let original = try #require(view.textSelectionNavigationState)
        try #require(original.extentOffset < original.anchorOffset)
        let selection = view.currentSelection

        #expect(view.vimSwapTextSelectionEndpoint())
        #expect(view.currentSelection === selection)
        #expect(view.textSelectionNavigationState?.anchorOffset == original.extentOffset)
        #expect(view.textSelectionNavigationState?.extentOffset == original.anchorOffset)
        #expect(view.vimNavigateTextSelection("l"))
        #expect(view.textSelectionNavigationState?.anchorOffset == original.extentOffset)
        #expect(view.textSelectionNavigationState?.extentOffset == original.anchorOffset + 1)
    }

    @Test(arguments: ["j", "k"])
    func followingVerticalMotionUsesTheSwappedCaret(key: String) throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        let range = try #require(page.string as NSString?).range(of: "seventh")
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: range), animate: false)

        #expect(view.vimSwapTextSelectionEndpoint())
        #expect(view.vimNavigateTextSelection(key))

        let state = try #require(view.textSelectionNavigationState)
        #expect(state.anchorOffset == range.location + range.length)
        #expect(key == "j" ? state.extentOffset > state.anchorOffset : state.extentOffset < range.location)
        #expect(state.preferredX != nil)
    }

    @Test(arguments: [0, 90, 180, 270])
    func crossPageSelectionPreservesRegionAndAdjustsFirstPageEndpoint(rotation: Int) async throws {
        _ = NSApplication.shared
        let document = try makeDocument()
        for pageIndex in 0..<document.pageCount {
            document.page(at: pageIndex)?.rotation = rotation
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        defer {
            view.cancelPendingRestore()
            view.stopZoomState()
            view.stopScrollAnimation()
            window.contentView = nil
            window.close()
        }
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 0.8
        view.layoutDocumentView()
        await nextTestMainQueueTurn()
        let pageStarts = view.textPageStarts(in: document)
        let start = pageStarts[1] - 5
        let end = pageStarts[1] + 6
        #expect(view.applyTextSelection(anchorOffset: start, extentOffset: end,
                                       pageStarts: pageStarts, scrollToEndpoint: false))
        let selection = try #require(view.currentSelection)
        let clip = try #require(view.pdfScrollView).contentView
        let origin = clip.bounds.origin

        #expect(view.vimSwapTextSelectionEndpoint())

        #expect(view.currentSelection === selection)
        #expect(view.currentSelection?.pages.count == 2)
        #expect(clip.bounds.origin == origin)
        #expect(view.textSelectionNavigationState?.anchorOffset == end)
        #expect(view.textSelectionNavigationState?.extentOffset == start)
        #expect(view.vimNavigateTextSelection("h"))
        #expect(view.textSelectionNavigationState?.anchorOffset == end)
        #expect(view.textSelectionNavigationState?.extentOffset == start - 1)
        #expect(view.currentSelection?.pages.count == 2)
    }

    private func makeDocument() throws -> PDFDocument {
        try makeTextPDF(pages: [[
            ("first second third fourth fifth", NSPoint(x: 72, y: 720)),
            ("sixth seventh eighth ninth tenth", NSPoint(x: 72, y: 690))
        ], [("another selectable page", NSPoint(x: 72, y: 720))]])
    }
}

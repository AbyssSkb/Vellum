import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF selection line boundaries")
struct PDFSelectionLineBoundaryTests {
    @Test(arguments: ["^", "$"])
    func noSelectionDoesNotCreateNavigationState(key: String) throws {
        let view = VellumPDFView(frame: .zero)
        view.document = try makeDocument()

        #expect(!view.vimNavigateTextSelection(key))
        #expect(view.currentSelection == nil)
        #expect(view.textSelectionNavigationState == nil)
    }

    @Test
    func caretMovesToFirstNonblankAndKeepsTheAnchor() throws {
        let (view, page, text) = try makeReader()
        let anchor = text.range(of: "beta").location
        let secondLine = text.range(of: "delta")
        let extent = text.range(of: "epsilon").location + 4
        view.setCurrentSelection(page.selection(for: NSRange(location: anchor, length: extent - anchor)), animate: false)

        #expect(view.vimNavigateTextSelection("^"))

        #expect(view.textSelectionNavigationState?.anchorOffset == anchor)
        #expect(view.textSelectionNavigationState?.extentOffset == secondLine.location)
        #expect(view.textSelectionNavigationState?.preferredX == nil)
    }

    @Test
    func dollarIncludesLastCharacterAndIgnoresCount() throws {
        let (view, page, text) = try makeReader()
        let range = text.range(of: "beta")
        view.setCurrentSelection(page.selection(for: range), animate: false)

        #expect(view.vimNavigateTextSelection("$", count: Int.max))

        let end = NSMaxRange(text.range(of: "gamma"))
        #expect(view.textSelectionNavigationState?.anchorOffset == range.location)
        #expect(view.textSelectionNavigationState?.extentOffset == end)
        #expect(view.currentSelection?.string == "beta gamma")
        #expect(view.vimNavigateTextSelection("$"))
        #expect(view.textSelectionNavigationState?.extentOffset == end)
    }

    @Test
    func swappedEndpointMovesToFirstNonblankWithoutMovingTheAnchor() throws {
        let (view, page, text) = try makeReader()
        let range = text.range(of: "epsilon")
        view.setCurrentSelection(page.selection(for: range), animate: false)
        #expect(view.vimSwapTextSelectionEndpoint())

        #expect(view.vimNavigateTextSelection("^", count: 8))

        #expect(view.textSelectionNavigationState?.anchorOffset == NSMaxRange(range))
        #expect(view.textSelectionNavigationState?.extentOffset == text.range(of: "delta").location)
        #expect(view.currentSelection?.string == "delta epsilon")
    }

    @Test(arguments: [("^", false), ("$", true)])
    func boundaryAtAnchorKeepsTheSelectionInsteadOfCrossingIt(motion: (String, Bool)) throws {
        let (view, page, text) = try makeReader()
        let range = text.range(of: "alpha beta gamma")
        view.setCurrentSelection(page.selection(for: range), animate: false)
        if motion.1 { #expect(view.vimSwapTextSelectionEndpoint()) }
        let selection = view.currentSelection

        #expect(view.vimNavigateTextSelection(motion.0))
        #expect(view.currentSelection === selection)
        #expect(view.currentSelection?.string == "alpha beta gamma")
    }

    @Test(arguments: ["left", "right"], ["^", "$"])
    func lineBoundaryStaysInsideTheCurrentColumn(column: String, key: String) throws {
        let document = try makeTextPDF(pages: [[
            ("left middle ending", NSPoint(x: 72, y: 720)),
            ("right center final", NSPoint(x: 340, y: 720))
        ]])
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string as NSString?)
        let word = column == "left" ? "middle" : "center"
        let range = text.range(of: word)
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: range), animate: false)
        if key == "^" { #expect(view.vimSwapTextSelectionEndpoint()) }

        #expect(view.vimNavigateTextSelection(key))

        let expected = key == "^" ? text.range(of: column).location
            : NSMaxRange(text.range(of: column == "left" ? "ending" : "final"))
        #expect(view.textSelectionNavigationState?.extentOffset == expected)
        #expect(view.currentSelection?.string?.contains(column == "left" ? "right" : "left") == false)
    }

    @Test(arguments: [0, 90, 180, 270], ["^", "$"])
    func rotationUsesTheActiveVisualLine(rotation: Int, key: String) throws {
        let (view, page, text) = try makeReader(rotation: rotation)
        let range = text.range(of: "beta")
        view.setCurrentSelection(page.selection(for: range), animate: false)
        if key == "^" { #expect(view.vimSwapTextSelectionEndpoint()) }
        let pageStarts = view.textPageStarts(in: try #require(view.document))
        let original = try #require(view.textSelectionState(pageStarts: pageStarts))
        let active = try #require(original.extentCaret)
        let lines = view.textLines(onPageAt: active.pageIndex, pageStarts: pageStarts)
        let line = lines[try #require(view.lineIndex(for: active, fallbackOffset: active.offset, in: lines))]

        #expect(view.vimNavigateTextSelection(key))

        let state = try #require(view.textSelectionNavigationState)
        #expect(state.anchorOffset == original.anchorOffset)
        #expect(state.extentCaret?.pageIndex == active.pageIndex)
        #expect(abs(try #require(state.extentCaret?.lineMidY) - line.midY) < 0.5)
        #expect(state.extentOffset != state.anchorOffset)
        #expect(view.currentSelection?.string?.isEmpty == false)
        let selection = view.currentSelection?.string
        #expect(view.vimNavigateTextSelection(key))
        #expect(view.currentSelection?.string == selection)
    }

    private func makeDocument() throws -> PDFDocument {
        try makeTextPDF(pages: [[
            ("alpha beta gamma", NSPoint(x: 72, y: 720)),
            ("   delta epsilon zeta", NSPoint(x: 72, y: 690))
        ]])
    }

    private func makeReader(rotation: Int = 0) throws -> (VellumPDFView, PDFPage, NSString) {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        page.rotation = rotation
        let text = try #require(page.string as NSString?)
        let view = VellumPDFView(frame: .zero)
        view.document = document
        return (view, page, text)
    }
}

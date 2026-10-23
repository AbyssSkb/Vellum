import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF visual selection construction")
struct PDFVisualSelectionConstructionTests {
    @Test(arguments: [false, true])
    func visualSelectionRetainsNativePageRangesWhenAddingLines(reversed: Bool) throws {
        let document = try makeTextPDF(pages: [[
            ("alpha beta gamma", NSPoint(x: 72, y: 720)),
            ("delta epsilon zeta", NSPoint(x: 72, y: 690))
        ]])
        let view = VellumPDFView(frame: .zero)
        view.document = document
        let page = try #require(document.page(at: 0))
        let starts = view.textPageStarts(in: document)
        let text = try #require(page.string as NSString?)
        let leading = try #require(view.textCaret(
            atInsertionOffset: text.range(of: "beta").location, preferTrailingEdge: false, pageStarts: starts
        ))
        let trailing = try #require(view.textCaret(
            atInsertionOffset: NSMaxRange(text.range(of: "delta")), preferTrailingEdge: true, pageStarts: starts
        ))

        #expect(view.applyVisualTextSelection(
            anchorCaret: reversed ? trailing : leading,
            extentCaret: reversed ? leading : trailing,
            pageStarts: starts
        ))

        let selection = try #require(view.currentSelection)
        #expect(selection.pages.count == 1)
        #expect(selection.pages.first === page)
        #expect(selection.string?.contains("beta gamma") == true)
        #expect(selection.string?.contains("delta") == true)
        #expect(selection.string?.contains("alpha") == false)
        #expect(selection.string?.contains("epsilon") == false)
    }
}

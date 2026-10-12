import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("Hyphenated word selection")
struct HyphenatedWordSelectionTests {
    @Test(arguments: ["wor", "d"])
    @MainActor
    func rangeExtendsAcrossSoftHyphenLineBreak(fragment: String) {
        let text = "The wor-\nd continues." as NSString
        let selectedRange = text.range(of: fragment)

        let range = VellumPDFView.hyphenatedWordRange(in: text, selectedRange: selectedRange)

        #expect(text.substring(with: range) == "wor-\nd")
    }

    @Test
    @MainActor
    func rangeDoesNotExtendRegularInlineHyphenatedWords() {
        let text = "A well-made reader." as NSString
        let selectedRange = text.range(of: "well")

        let range = VellumPDFView.hyphenatedWordRange(in: text, selectedRange: selectedRange)

        #expect(text.substring(with: range) == "well")
    }

    @Test(arguments: ["wor", "d"])
    @MainActor
    func smartSelectionSelectsWholeWordFromEitherFragmentInPDF(fragment: String) throws {
        let document = try makeTextPDF(pages: [[
            ("The broken wor-", NSPoint(x: 72, y: 720)),
            ("d appears below.", NSPoint(x: 72, y: 693))
        ]])
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.document = document
        let pageText = try #require(page.string as NSString?)
        let expectedRange = try #require(foundRange(pageText.range(of: "wor-\nd")))
        let fragmentRange = try #require(foundRange(pageText.range(
            of: fragment,
            options: [],
            range: NSRange(location: expectedRange.location, length: expectedRange.length)
        )))
        let fragmentBounds = try #require(page.selection(for: fragmentRange)?.bounds(for: page))

        let selection = try #require(view.smartWordSelection(at: center(of: fragmentBounds), on: page))

        #expect(selection.string == pageText.substring(with: expectedRange))
    }

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    private func foundRange(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }
}

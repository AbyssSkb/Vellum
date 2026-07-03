import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("Hyphenated word selection")
struct HyphenatedWordSelectionTests {
    @Test
    @MainActor
    func rangeExtendsForwardAcrossSoftHyphenLineBreak() {
        let text = "The wor-\nd continues." as NSString
        let selectedRange = text.range(of: "wor")

        let range = VellumPDFView.hyphenatedWordRange(in: text, selectedRange: selectedRange)

        #expect(text.substring(with: range) == "wor-\nd")
    }

    @Test
    @MainActor
    func rangeExtendsBackwardAcrossSoftHyphenLineBreak() {
        let text = "The wor-\nd continues." as NSString
        let selectedRange = text.range(of: "d")

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

    @Test
    @MainActor
    func smartSelectionSelectsWholeWordFromFirstFragmentInPDF() throws {
        let document = try makeHyphenatedPDFDocument()
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.document = document
        let pageText = try #require(page.string as NSString?)
        let expectedRange = try #require(foundRange(pageText.range(of: "wor-\nd")))
        let firstFragmentRange = try #require(foundRange(pageText.range(of: "wor")))
        let fragmentBounds = try #require(page.selection(for: firstFragmentRange)?.bounds(for: page))

        let selection = try #require(view.smartWordSelection(at: center(of: fragmentBounds), on: page))

        #expect(selection.string == pageText.substring(with: expectedRange))
    }

    @Test
    @MainActor
    func smartSelectionSelectsWholeWordFromSecondFragmentInPDF() throws {
        let document = try makeHyphenatedPDFDocument()
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.document = document
        let pageText = try #require(page.string as NSString?)
        let expectedRange = try #require(foundRange(pageText.range(of: "wor-\nd")))
        let secondFragmentRange = try #require(foundRange(pageText.range(
            of: "d",
            options: [],
            range: NSRange(location: expectedRange.location, length: expectedRange.length)
        )))
        let fragmentBounds = try #require(page.selection(for: secondFragmentRange)?.bounds(for: page))

        let selection = try #require(view.smartWordSelection(at: center(of: fragmentBounds), on: page))

        #expect(selection.string == pageText.substring(with: expectedRange))
    }

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    private func foundRange(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }

    private func makeHyphenatedPDFDocument() throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18)
        ]
        ("The broken wor-" as NSString).draw(at: NSPoint(x: 72, y: 720), withAttributes: attributes)
        ("d appears below." as NSString).draw(at: NSPoint(x: 72, y: 693), withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return try #require(PDFDocument(data: data as Data))
    }
}

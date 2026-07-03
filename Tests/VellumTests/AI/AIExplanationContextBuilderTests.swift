import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("AI explanation context builder")
struct AIExplanationContextBuilderTests {
    @Test
    @MainActor
    func contextNormalizesSelectedPDFTextBeforePrompting() throws {
        let document = try makePDFDocument(lines: [
            "The selected paragraph is split",
            "across PDF visual lines."
        ])
        let page = try #require(document.page(at: 0))
        let pageText = try #require(page.string as NSString?)
        let startRange = try #require(foundRange(pageText.range(of: "selected")))
        let endRange = try #require(foundRange(pageText.range(of: "lines.")))
        let selectedRange = NSRange(
            location: startRange.location,
            length: endRange.location + endRange.length - startRange.location
        )
        let selection = try #require(page.selection(for: selectedRange))

        let context = try #require(AIExplanationContextBuilder.context(
            for: selection,
            selectedText: selection.string ?? "",
            document: document
        ))

        #expect(context.selectedText == "selected paragraph is split across PDF visual lines.")
        #expect(context.anchoredContext?.contains("<selected>selected paragraph is split across PDF visual lines.</selected>") == true)
        #expect(context.prompt.contains("<selected_text>\nselected paragraph is split across PDF visual lines.\n</selected_text>"))
    }

    private func foundRange(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }

    private func makePDFDocument(lines: [String]) throws -> PDFDocument {
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
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 72, y: 720 - index * 27), withAttributes: attributes)
        }

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return try #require(PDFDocument(data: data as Data))
    }
}

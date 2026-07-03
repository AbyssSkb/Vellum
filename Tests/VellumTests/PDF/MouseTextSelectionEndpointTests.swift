import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("Mouse text selection endpoint")
struct MouseTextSelectionEndpointTests {
    @Test
    @MainActor
    func middleLineCharacterPointsProduceCoveredTextRange() throws {
        let document = try makeSimplePDFDocument()
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.document = document
        let pageStarts = view.textPageStarts(in: document)

        let pageText = try #require(page.string as NSString?)
        let marker = "Line 8: Vellum selection" as NSString
        let markerRange = try #require(foundRange(pageText.range(of: marker as String)))

        let selectionWordRange = try #require(foundRange(marker.range(of: "selection")))
        let selectionStart = markerRange.location + selectionWordRange.location
        let scrollingRange = try #require(foundRange(pageText.range(
            of: "scrolling",
            options: [],
            range: NSRange(location: markerRange.location, length: min(120, pageText.length - markerRange.location))
        )))
        let scrollingEnd = scrollingRange.location + scrollingRange.length - 1

        let anchorBounds = try #require(page.selection(for: NSRange(location: selectionStart, length: 1))?.bounds(for: page))
        let extentBounds = try #require(page.selection(for: NSRange(location: scrollingEnd, length: 1))?.bounds(for: page))
        let anchor = try #require(view.mouseTextSelectionEndpoint(
            on: page,
            pageIndex: 0,
            pointOnPage: center(of: anchorBounds),
            requiresCharacterHit: true,
            pageStarts: pageStarts
        ))
        let extent = try #require(view.mouseTextSelectionEndpoint(
            on: page,
            pageIndex: 0,
            pointOnPage: center(of: extentBounds),
            requiresCharacterHit: false,
            pageStarts: pageStarts
        ))

        let range = try #require(MouseTextSelectionEndpoint.selectionRange(anchor: anchor, extent: extent))
        #expect(range.start == selectionStart)
        #expect(range.end == scrollingEnd + 1)

        #expect(view.applyTextSelection(
            anchorOffset: range.start,
            extentOffset: range.end,
            pageStarts: pageStarts,
            scrollToEndpoint: false
        ))
        #expect(view.currentSelection?.string == "selection wheel scrolling")
    }

    @Test
    func endpointRangeIncludesCharactersInReverseDrags() throws {
        let anchor = MouseTextSelectionEndpoint(lowerOffset: 30, upperOffset: 31)
        let extent = MouseTextSelectionEndpoint(lowerOffset: 10, upperOffset: 11)

        let range = try #require(MouseTextSelectionEndpoint.selectionRange(anchor: anchor, extent: extent))

        #expect(range.start == 10)
        #expect(range.end == 31)
    }

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    private func foundRange(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }

    private func makeSimplePDFDocument() throws -> PDFDocument {
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
        let lineTemplate = "Line 1: Vellum selection wheel scrolling should expand and shrink this text selection smoothly."
        for lineNumber in 1...12 {
            let line = lineTemplate.replacingOccurrences(of: "Line 1", with: "Line \(lineNumber)") as NSString
            line.draw(at: NSPoint(x: 72, y: 720 - lineNumber * 27), withAttributes: attributes)
        }

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return try #require(PDFDocument(data: data as Data))
    }
}

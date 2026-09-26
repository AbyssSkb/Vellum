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
            requiresCharacterHit: true
        ))
        let extent = try #require(view.mouseTextSelectionEndpoint(
            on: page,
            pageIndex: 0,
            pointOnPage: center(of: extentBounds),
            requiresCharacterHit: false
        ))

        let range = try #require(MouseTextSelectionEndpoint.selectionRange(anchor: anchor, extent: extent))
        #expect(range.start == selectionStart)
        #expect(range.end == scrollingEnd + 1)

        #expect(view.applyMouseTextSelection(anchor: anchor, extent: extent))
        #expect(view.currentSelection?.string == "selection wheel scrolling")
    }

    @Test
    func endpointRangeIncludesCharactersInReverseDrags() throws {
        let anchor = MouseTextSelectionEndpoint(pageIndex: 0, lowerOffset: 30, upperOffset: 31)
        let extent = MouseTextSelectionEndpoint(pageIndex: 0, lowerOffset: 10, upperOffset: 11)

        let range = try #require(MouseTextSelectionEndpoint.selectionRange(anchor: anchor, extent: extent))

        #expect(range.start == 10)
        #expect(range.end == 31)
    }

    @Test
    @MainActor
    func pageLocalEndpointsPreserveCrossPageSelectionInBothDirections() throws {
        let document = try makeSimplePDFDocument()
        let secondDocument = try makeSimplePDFDocument()
        let firstPage = try #require(document.page(at: 0))
        let secondPage = try #require(secondDocument.page(at: 0))
        document.insert(secondPage, at: 1)
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.document = document

        let start = MouseTextSelectionEndpoint(
            pageIndex: 0,
            lowerOffset: firstPage.numberOfCharacters - 5,
            upperOffset: firstPage.numberOfCharacters - 4
        )
        let end = MouseTextSelectionEndpoint(pageIndex: 1, lowerOffset: 3, upperOffset: 4)
        let expected = try #require(document.selection(
            from: firstPage,
            atCharacterIndex: start.lowerOffset,
            to: secondPage,
            atCharacterIndex: end.upperOffset - 1
        )?.string)

        #expect(view.applyMouseTextSelection(anchor: start, extent: end))
        #expect(view.currentSelection?.string == expected)
        #expect(view.applyMouseTextSelection(anchor: end, extent: start))
        #expect(view.currentSelection?.string == expected)

        let caretAtNextPageStart = MouseTextSelectionEndpoint(pageIndex: 1, lowerOffset: 0, upperOffset: 0)
        #expect(view.applyMouseTextSelection(anchor: start, extent: caretAtNextPageStart))
        #expect(view.currentSelection?.string == firstPage.selection(for: NSRange(
            location: start.lowerOffset,
            length: firstPage.numberOfCharacters - start.lowerOffset
        ))?.string)
    }

    @Test
    @MainActor
    func clickingTextDoesNotReadOtherPagesCharacters() throws {
        _ = NSApplication.shared
        let document = try makeSimplePDFDocument()
        let page = try #require(document.page(at: 0))
        let unreadPage = CharacterReadCountingPage()
        document.insert(unreadPage, at: 1)
        let window = MouseSelectionWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.document = document
        view.scaleFactor = 1
        view.layoutDocumentView()
        let bounds = try #require(page.selection(for: NSRange(location: 0, length: 1))?.bounds(for: page))
        let point = view.convert(view.convert(center(of: bounds), from: page), to: nil)
        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        window.mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0
        ))
        unreadPage.characterReadCount = 0

        view.mouseDown(with: mouseDown)

        #expect(unreadPage.characterReadCount == 0)
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

private final class CharacterReadCountingPage: PDFPage {
    var characterReadCount = 0

    override var numberOfCharacters: Int {
        characterReadCount += 1
        return super.numberOfCharacters
    }
}

private final class MouseSelectionWindow: NSWindow {
    var mouseUp: NSEvent?

    override func nextEvent(
        matching mask: NSEvent.EventTypeMask,
        until expiration: Date?,
        inMode mode: RunLoop.Mode,
        dequeue deqFlag: Bool
    ) -> NSEvent? {
        mouseUp
    }
}

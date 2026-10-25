@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Bibliography entry geometry")
struct PDFBibliographyLayoutTests {
    @Test(arguments: ["Alex Morgan.", "MAA."])
    func justifiedFirstRowsRetainEveryFragmentAndContinuation(author: String) throws {
        let fixture = try fixture(lines: [
            ("Previous Author. Earlier publication, 2020.", CGPoint(x: 55, y: 650)),
            (author, CGPoint(x: 55, y: 610)),
            ("A complete", CGPoint(x: 155, y: 610)),
            ("study title.", CGPoint(x: 235, y: 610)),
            ("Conference 2021. URL example.org/paper.", CGPoint(x: 65, y: 594)),
            ("The final continuation.", CGPoint(x: 65, y: 578)),
            ("Next Author. Another publication, 2022.", CGPoint(x: 55, y: 554)),
            ("Its unrelated continuation.", CGPoint(x: 65, y: 538))
        ], first: author)

        let bounds = try resolvedBounds(fixture)

        for text in [author, "A complete", "study title.", "Conference 2021.", "The final continuation."] {
            #expect(bounds.contains(try visibleBounds(text, on: fixture.page)))
        }
        for text in ["Previous Author.", "Next Author.", "Its unrelated continuation."] {
            #expect(!bounds.intersects(try visibleBounds(text, on: fixture.page)))
        }
    }

    @Test
    func anAnchorNearTheGutterSelectsTheRightEntryInsteadOfLeftBodyText() throws {
        let fixture = try fixture(lines: [
            ("Ordinary body text spans most of the left column.", CGPoint(x: 55, y: 610)),
            ("It has no bibliography date or author.", CGPoint(x: 55, y: 594)),
            ("Its discussion continues on another line.", CGPoint(x: 55, y: 578)),
            ("Alex Morgan. The intended publication.", CGPoint(x: 310, y: 610)),
            ("Conference 2021. URL example.org/paper.", CGPoint(x: 320, y: 594)),
            ("Next Author. Another publication, 2022.", CGPoint(x: 310, y: 570)),
            ("Its unrelated continuation.", CGPoint(x: 320, y: 554))
        ], first: "Alex Morgan.", destinationX: 290)

        let bounds = try resolvedBounds(fixture)

        #expect(bounds.contains(try visibleBounds("Alex Morgan.", on: fixture.page)))
        #expect(bounds.contains(try visibleBounds("Conference 2021.", on: fixture.page)))
        #expect(!bounds.intersects(try visibleBounds("Ordinary body text", on: fixture.page)))
        #expect(!bounds.intersects(try visibleBounds("Next Author.", on: fixture.page)))
    }

    @Test
    func anOverflowingEntryKeepsPageContextWhenItsRectangleContainsAnotherColumn() throws {
        let fixture = try fixture(lines: [
            ("Alex Morgan. The intended publication.", CGPoint(x: 55, y: 610)),
            ("Conference 2021. URL", CGPoint(x: 65, y: 594)),
            ("https://example.org/a-very-long-unbroken-publication-address", CGPoint(x: 65, y: 578)),
            ("Next Author. Another publication, 2022.", CGPoint(x: 55, y: 554)),
            ("Its unrelated continuation.", CGPoint(x: 65, y: 538)),
            ("Right Author. A different publication, 2020.", CGPoint(x: 310, y: 610)),
            ("Right column continuation.", CGPoint(x: 320, y: 594)),
            ("Another right entry, 2023.", CGPoint(x: 310, y: 570)),
            ("Its final continuation.", CGPoint(x: 320, y: 554))
        ], first: "Alex Morgan.")

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("An ambiguous crop must preserve page context instead of including adjacent text")
            return
        }
    }

    @Test
    func aDatedCitationDoesNotTreatAnAuthorsOnlyFragmentAsACompleteEntry() throws {
        let fixture = try fixture(lines: [
            ("Alex Morgan, Jamie Writer, and other authors.", CGPoint(x: 55, y: 610)),
            ("Several more authors continue here.", CGPoint(x: 65, y: 594)),
            ("Next Author. Another publication, 2022.", CGPoint(x: 55, y: 570)),
            ("Its unrelated continuation.", CGPoint(x: 65, y: 554))
        ], first: "Alex Morgan,")

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A dated citation without its year may continue in another column or page")
            return
        }
    }

    @Test(arguments: [false, true])
    func aPageBreakRetainsTheCompleteEntryIncludingItsDateAndURL(dateOnFirstPage: Bool) throws {
        let fixture = try fixture(lines: [
            ("Alex Morgan and several coauthors.", CGPoint(x: 55, y: 88)),
            (dateOnFirstPage ? "J. Writer. A complete publication, 2021. URL" : "J. Writer. A publication title continues", CGPoint(x: 65, y: 72)),
            ("2", CGPoint(x: 300, y: 30))
        ], first: "Alex Morgan", continuation: [
            (dateOnFirstPage ? "https://example.org/a-complete-publication" : "on the next page. Conference 2021.", CGPoint(x: 65, y: 730)),
            ("07372. URL https://example.org/final-address.", CGPoint(x: 65, y: 714)),
            ("Next Author. A different publication, 2022.", CGPoint(x: 55, y: 690)),
            ("Its continuation is unrelated.", CGPoint(x: 65, y: 674))
        ])

        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A bibliography entry can continue on the next page")
            return
        }
        let continuation = try #require(region.continuation)
        let nextPage = try #require(fixture.document.page(at: 2))
        let footer = try #require(PDFReferenceTextLayout.lines(on: fixture.page).first { $0.text == "2" })
        #expect(continuation.page === nextPage)
        #expect(region.bounds.contains(try visibleBounds("Alex Morgan", on: fixture.page)))
        #expect(!region.bounds.intersects(footer.bounds))
        #expect(continuation.bounds.contains(try visibleBounds("final-address.", on: nextPage)))
        #expect(!continuation.bounds.intersects(try visibleBounds("Next Author.", on: nextPage)))
    }

    @Test
    func anUnprovenPageBreakKeepsPageContext() throws {
        let fixture = try fixture(lines: [
            ("Alex Morgan and several coauthors.", CGPoint(x: 55, y: 88)),
            ("A publication title continues", CGPoint(x: 65, y: 72))
        ], first: "Alex Morgan", continuation: [
            ("An indented unrelated fragment has no matching year.", CGPoint(x: 65, y: 730)),
            ("Next Author. A different publication, 2022.", CGPoint(x: 55, y: 706)),
            ("Its continuation is unrelated.", CGPoint(x: 65, y: 690))
        ])

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A page break requires matching bibliography evidence")
            return
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func fixture(lines: [(String, CGPoint)], first: String, destinationX: CGFloat? = nil,
                         continuation: [(String, CGPoint)]? = nil) throws -> Fixture {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &media, nil))
        let pages = [[("See (Morgan et al., 2021).", CGPoint(x: 40, y: 700))], lines] + (continuation.map { [$0] } ?? [])
        for content in pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (text, point) in content {
                (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let source = try #require(document.page(at: 0))
        let page = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try textBounds("2021", on: source), forType: .link, withProperties: nil)
        source.addAnnotation(annotation)
        let start = try textBounds(first, on: page)
        let destination = PDFDestination(page: page, at: CGPoint(x: destinationX ?? start.minX - 20, y: start.maxY + 4))
        annotation.destination = destination
        return Fixture(document: document, page: page, annotation: annotation, destination: destination)
    }

    private func resolvedBounds(_ fixture: Fixture) throws -> CGRect {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A bibliography entry should retain its whole first row and continuations")
            throw MissingRegion()
        }
        return region.bounds
    }

    private func visibleBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let lines = PDFReferenceTextLayout.lines(on: page).filter { $0.text.contains(text) }
        try #require(!lines.isEmpty)
        return lines.reduce(CGRect.null) { $0.union($1.bounds) }
    }

    private func textBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private struct MissingRegion: Error {}
}

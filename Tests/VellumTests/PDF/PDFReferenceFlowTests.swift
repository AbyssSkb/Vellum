@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reference reading flow")
struct PDFReferenceFlowTests {
    @Test
    func aSectionContinuesInTheNextColumnBeforeTheNextPage() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 130), 18),
            ("The paragraph continues", CGPoint(x: 72, y: 106), 18),
            ("through the remaining", CGPoint(x: 72, y: 82), 18),
            ("right column context.", CGPoint(x: 330, y: 700), 18),
            ("The final sentence.", CGPoint(x: 330, y: 676), 18),
            ("A separate paragraph.", CGPoint(x: 342, y: 628), 18)
        ], following: [
            ("Unrelated next page.", CGPoint(x: 72, y: 700), 18),
            ("Its separate context.", CGPoint(x: 72, y: 676), 18)
        ])

        let region = try resolvedRegion(fixture)
        let continuation = try #require(region.continuation)

        #expect(continuation.page === fixture.target)
        #expect(continuation.bounds.contains(try bounds("right column context.", on: fixture.target)))
        #expect(continuation.bounds.contains(try bounds("The final sentence.", on: fixture.target)))
        #expect(!continuation.bounds.intersects(try bounds("A separate paragraph.", on: fixture.target)))
    }

    @Test
    func aRejectedFirstRowCannotBeSkippedToJoinALaterParagraph() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 130), 18),
            ("The paragraph describes", CGPoint(x: 72, y: 106), 18),
            ("an unfinished result", CGPoint(x: 72, y: 82), 18)
        ], following: [
            ("3 Results", CGPoint(x: 72, y: 700), 24),
            ("A different section begins.", CGPoint(x: 72, y: 664), 18),
            ("Its paragraph continues.", CGPoint(x: 72, y: 640), 18)
        ])

        let region = try resolvedRegion(fixture)

        #expect(region.continuation == nil)
    }

    @Test
    func aContinuationKeepsTheFirstLineWhenItsGlyphHeightChanges() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 130), 18),
            ("The paragraph describes", CGPoint(x: 72, y: 106), 18),
            ("the remaining result", CGPoint(x: 72, y: 82), 18)
        ], following: [
            ("with its complete context.", CGPoint(x: 72, y: 700), 20),
            ("The final sentence.", CGPoint(x: 72, y: 674), 18),
            ("A separate paragraph.", CGPoint(x: 84, y: 626), 18),
            ("Its unrelated continuation.", CGPoint(x: 72, y: 602), 18)
        ])

        let region = try resolvedRegion(fixture)
        let continuation = try #require(region.continuation)

        #expect(continuation.page === fixture.following)
        #expect(continuation.bounds.contains(try bounds("with its complete context.", on: fixture.following)))
        #expect(continuation.bounds.contains(try bounds("The final sentence.", on: fixture.following)))
        #expect(!continuation.bounds.intersects(try bounds("A separate paragraph.", on: fixture.following)))
        #expect(!continuation.bounds.intersects(try bounds("Its unrelated continuation.", on: fixture.following)))
    }

    @Test
    func aHeadingInTheNextColumnStopsBeforeTheNextPhysicalPage() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 130), 18),
            ("The paragraph trails", CGPoint(x: 72, y: 106), 18),
            ("toward the next column", CGPoint(x: 72, y: 82), 18),
            ("3 Results", CGPoint(x: 330, y: 700), 24),
            ("A different section.", CGPoint(x: 330, y: 664), 18)
        ], following: [
            ("Unrelated next page.", CGPoint(x: 72, y: 700), 18),
            ("Its separate context.", CGPoint(x: 72, y: 676), 18)
        ])

        #expect(try resolvedRegion(fixture).continuation == nil)
    }

    @Test
    func aRightColumnContinuesIntoTheNextPagesLeftColumn() throws {
        let fixture = try makeFixture(target: [
            ("Unrelated left column.", CGPoint(x: 72, y: 700), 18),
            ("Its separate context.", CGPoint(x: 72, y: 676), 18),
            ("2 Method", CGPoint(x: 330, y: 130), 18),
            ("The paragraph describes", CGPoint(x: 330, y: 106), 18),
            ("the remaining result", CGPoint(x: 330, y: 82), 18)
        ], following: [
            ("with the complete context.", CGPoint(x: 72, y: 700), 18),
            ("The final sentence.", CGPoint(x: 72, y: 676), 18),
            ("An unrelated right column.", CGPoint(x: 330, y: 700), 18),
            ("Its separate context.", CGPoint(x: 330, y: 676), 18)
        ], point: CGPoint(x: 330, y: 142))

        let continuation = try #require(try resolvedRegion(fixture).continuation)

        #expect(continuation.page === fixture.following)
        #expect(continuation.bounds.contains(try bounds("with the complete context.", on: fixture.following)))
        #expect(!continuation.bounds.intersects(try bounds("An unrelated right column.", on: fixture.following)))
    }

    @Test
    func aFloatingDiagramDoesNotHideTheFirstParagraphContinuation() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 130), 18),
            ("The paragraph describes", CGPoint(x: 72, y: 106), 18),
            ("the remaining result", CGPoint(x: 72, y: 82), 18)
        ], following: [
            ("Diagram labels and values", CGPoint(x: 100, y: 720), 12),
            ("Figure 1: An unrelated diagram.", CGPoint(x: 72, y: 670), 18),
            ("with its complete context.", CGPoint(x: 72, y: 610), 18),
            ("The final sentence.", CGPoint(x: 72, y: 586), 18),
            ("A separate paragraph.", CGPoint(x: 84, y: 538), 18)
        ])

        let continuation = try #require(try resolvedRegion(fixture).continuation)

        #expect(continuation.bounds.contains(try bounds("with its complete context.", on: fixture.following)))
        #expect(continuation.bounds.contains(try bounds("The final sentence.", on: fixture.following)))
        #expect(!continuation.bounds.intersects(try bounds("Diagram labels and values", on: fixture.following)))
        #expect(!continuation.bounds.intersects(try bounds("A separate paragraph.", on: fixture.following)))
    }

    @Test
    func aFramedObjectCannotBecomeAParagraphContinuation() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 130), 18),
            ("The paragraph describes", CGPoint(x: 72, y: 106), 18),
            ("the remaining result", CGPoint(x: 72, y: 82), 18)
        ], following: [
            ("A boxed adjacent object.", CGPoint(x: 72, y: 700), 18),
            ("Its independent content.", CGPoint(x: 72, y: 676), 18),
            ("The true continuation follows below.", CGPoint(x: 72, y: 580), 18)
        ], followingFrame: CGRect(x: 68, y: 650, width: 290, height: 80))

        #expect(try resolvedRegion(fixture).continuation == nil)
    }

    @Test
    func aCompletedCenteredBlockDoesNotAppendTheNextParagraph() throws {
        let fixture = try makeFixture(target: [
            ("2 Method", CGPoint(x: 72, y: 180), 18),
            ("The complete calculation uses the following expressions:", CGPoint(x: 72, y: 156), 18),
            ("x = y (1)", CGPoint(x: 180, y: 132), 18),
            ("y = z (2)", CGPoint(x: 180, y: 108), 18)
        ], following: [
            ("A separate paragraph introduces a different calculation:", CGPoint(x: 72, y: 700), 18)
        ], point: CGPoint(x: 72, y: 192))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try bounds("x = y (1)", on: fixture.target)))
        #expect(region.bounds.contains(try bounds("y = z (2)", on: fixture.target)))
        #expect(region.continuation == nil)
    }

    private struct Fixture {
        let document: PDFDocument
        let target: PDFPage
        let following: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func makeFixture(target: [(String, CGPoint, CGFloat)], following: [(String, CGPoint, CGFloat)], point: CGPoint = CGPoint(x: 72, y: 142), followingFrame: CGRect? = nil) throws -> Fixture {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for (index, lines) in [[("See Section 2.", CGPoint(x: 40, y: 650), CGFloat(18))], target, following].enumerated() {
            context.beginPDFPage(nil)
            if index == 2, let frame = followingFrame {
                let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                               CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
                for edge in corners.indices {
                    context.move(to: corners[edge])
                    context.addLine(to: corners[(edge + 1) % corners.count])
                    context.strokePath()
                }
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (text, point, size) in lines {
                let font = try #require(NSFont(name: "Helvetica", size: size))
                (text as NSString).draw(at: point, withAttributes: [.font: font])
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let source = try #require(document.page(at: 0))
        let target = try #require(document.page(at: 1)), following = try #require(document.page(at: 2))
        let annotation = PDFAnnotation(bounds: try bounds("2", on: source), forType: .link, withProperties: nil)
        source.addAnnotation(annotation)
        let destination = PDFDestination(page: target, at: point)
        annotation.destination = destination
        return Fixture(document: document, target: target, following: following, annotation: annotation, destination: destination)
    }

    private func resolvedRegion(_ fixture: Fixture) throws -> PDFReferencePreview.Region {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The section must retain its content region")
            throw MissingRegion()
        }
        return region
    }

    private func bounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private struct MissingRegion: Error {}
}

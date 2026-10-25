@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF table preview boundaries")
struct PDFTablePreviewBoundaryTests {
    @Test(arguments: [false, true])
    func numericProseAboveABottomCaptionIsExcluded(hasRules: Bool) throws {
        let fixture = try makeFixture(captionAbove: false, hasRules: hasRules, surrounding: [
            ("We set a budget of 18M and adapt 4 weight matrices.", NSPoint(x: 72, y: 604)),
            ("We turn our attention to rank r and compare 2 settings.", NSPoint(x: 72, y: 590))
        ])

        let bounds = try resolvedBounds(fixture)

        try expectTableIncluded(in: bounds, fixture: fixture)
        for text in ["We set a budget", "We turn our attention"] {
            #expect(!bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test(arguments: [false, true])
    func proseAfterATopCaptionIsExcludedEvenWhenItContainsNumbers(hasRules: Bool) throws {
        let fixture = try makeFixture(captionAbove: true, hasRules: hasRules, surrounding: [
            ("The number of hidden features affects both model speed and cost.", NSPoint(x: 72, y: 512)),
            ("We extract features from 5 layers and evaluate 3 settings.", NSPoint(x: 72, y: 498))
        ])

        let bounds = try resolvedBounds(fixture)

        try expectTableIncluded(in: bounds, fixture: fixture)
        for text in ["The number of hidden", "We extract features"] {
            #expect(!bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test
    func ruledTablesRetainExplicitNotesOutsideTheBodyBorders() throws {
        let fixture = try makeFixture(captionAbove: true, hasRules: true, surrounding: [
            ("Note: Scores use the same split.", NSPoint(x: 72, y: 512)),
            ("The uncertainty is across random seeds.", NSPoint(x: 72, y: 498)),
            ("An unrelated paragraph discusses the model separately.", NSPoint(x: 72, y: 470))
        ])

        let bounds = try resolvedBounds(fixture)

        try expectTableIncluded(in: bounds, fixture: fixture)
        for text in ["Note:", "The uncertainty"] {
            #expect(bounds.contains(try textBounds(text, on: fixture.page)), "The table crop must contain \(text)")
        }
        #expect(!bounds.intersects(try textBounds("An unrelated paragraph", on: fixture.page)))
    }

    @Test
    func sparseRowsDoNotTruncateLaterTableGroups() throws {
        let fixture = try makeFixture(captionAbove: true, hasRules: true, surrounding: [
            ("Agentic tasks with tools", NSPoint(x: 72, y: 518)),
            ("-", NSPoint(x: 235, y: 518)),
            ("-", NSPoint(x: 280, y: 518)),
            ("-", NSPoint(x: 325, y: 518)),
            ("-", NSPoint(x: 370, y: 518)),
            ("-", NSPoint(x: 415, y: 518)),
            ("-", NSPoint(x: 460, y: 518)),
            ("-", NSPoint(x: 505, y: 518)),
            ("Final tool benchmark", NSPoint(x: 72, y: 498)),
            ("0.81", NSPoint(x: 260, y: 498)),
            ("0.79", NSPoint(x: 400, y: 498)),
            ("An unrelated paragraph follows the completed table.", NSPoint(x: 72, y: 460))
        ], ruleYs: [582, 560, 532, 492])

        let bounds = try resolvedBounds(fixture)

        try expectTableIncluded(in: bounds, fixture: fixture)
        for text in ["Agentic tasks with tools", "Final tool benchmark", "0.81", "0.79"] {
            #expect(bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)),
                    "The table crop must retain \(text) after a sparse row")
        }
        #expect(!bounds.intersects(try textBounds("An unrelated paragraph", on: fixture.page)))
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func makeFixture(captionAbove: Bool, hasRules: Bool,
                             surrounding: [(String, NSPoint)], ruleYs: [CGFloat] = [582, 560, 532]) throws -> Fixture {
        let captionY: CGFloat = captionAbove ? 612 : 508
        let content: [(String, NSPoint)] = [
            ("Table 2: Accuracy with the same parameter budget.", NSPoint(x: 72, y: captionY)),
            ("Weight Type", NSPoint(x: 72, y: 564)),
            ("r= 1 r= 2 r= 4 r= 8 r= 64", NSPoint(x: 190, y: 564)),
            ("1 Alpha", NSPoint(x: 72, y: 550)),
            ("0.91", NSPoint(x: 260, y: 550)),
            ("0.88", NSPoint(x: 400, y: 550)),
            ("2 Beta", NSPoint(x: 72, y: 536)),
            ("0.72", NSPoint(x: 260, y: 536)),
            ("0.69", NSPoint(x: 400, y: 536))
        ] + surrounding
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for lines in [[("See Table 2 for results.", NSPoint(x: 72, y: 650))], content] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (text, point) in lines {
                (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            }
            NSGraphicsContext.restoreGraphicsState()
            if hasRules, lines.count > 1 {
                for y in ruleYs {
                    context.move(to: CGPoint(x: 72, y: y))
                    context.addLine(to: CGPoint(x: 540, y: y))
                    context.strokePath()
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let source = try #require(document.page(at: 0))
        let page = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try textBounds("2", on: source), forType: .link, withProperties: nil)
        source.addAnnotation(annotation)
        let destination = PDFDestination(page: page, at: CGPoint(x: 72, y: captionY + 14))
        annotation.destination = destination
        return Fixture(document: document, page: page, annotation: annotation, destination: destination)
    }

    private func expectTableIncluded(in bounds: CGRect, fixture: Fixture) throws {
        for text in ["Table 2:", "Weight Type", "r= 1 r= 2 r= 4 r= 8 r= 64", "1 Alpha", "0.91", "0.88", "2 Beta", "0.72", "0.69"] {
            let expected = try textBounds(text, on: fixture.page)
            // PDFKit's selection bounds can extend slightly beyond the painted glyphs.
            #expect(bounds.insetBy(dx: -1, dy: -1).contains(expected), "The table crop must contain \(text)")
        }
    }

    private func resolvedBounds(_ fixture: Fixture) throws -> CGRect {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A table should resolve to a local content region")
            throw MissingRegion()
        }
        return region.bounds
    }

    private func textBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private struct MissingRegion: Error {}
}

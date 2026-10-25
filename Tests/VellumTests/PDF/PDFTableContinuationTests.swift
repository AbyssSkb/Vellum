@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF table continuation")
struct PDFTableContinuationTests {
    @Test(arguments: [false, true])
    func aFramedTableRetainsItsFollowingPagesAndStopsAtItsClosingRule(repeatedCaption: Bool) throws {
        let fixture = try fixture(nextCaption: false, repeatedCaption: repeatedCaption)
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A table must retain its complete framed content")
            return
        }
        let continuation = try #require(region.continuation)

        #expect(continuation.page === fixture.document.page(at: 2))
        #expect(continuation.bounds.contains(try bounds("middle page last row", on: continuation.page)))
        #expect(!continuation.bounds.intersects(try bounds("Running header", on: continuation.page)))
        let last = try #require(region.additionalFragments.first)
        #expect(region.additionalFragments.count == 1)
        #expect(last.page === fixture.document.page(at: 3))
        #expect(last.bounds.contains(try bounds("table page row 15", on: last.page)))
        #expect(!last.bounds.intersects(try bounds("Table 9", on: last.page)))
        #expect(!last.bounds.intersects(try bounds("Unrelated data", on: last.page)))
    }

    @Test
    func aNewCaptionPreventsJoiningAnAlignedTableOnTheNextPage() throws {
        let fixture = try fixture(nextCaption: true)
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The first table must retain its own region")
            return
        }

        #expect(region.continuation == nil)
    }

    @Test(arguments: ["A.2", "9b"])
    func aContinuationStopsBeforeAForeignAppendixOrSuffixedCaption(number: String) throws {
        let fixture = try fixture(nextCaption: false, foreignNumber: number)
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The original table must retain its content")
            return
        }
        let last = try #require(region.additionalFragments.first)

        #expect(last.page === fixture.document.page(at: 3))
        #expect(!last.bounds.intersects(try bounds("Table \(number)", on: last.page)))
        #expect(!last.bounds.intersects(try bounds("Unrelated data", on: last.page)))
    }

    @Test
    func aSmallCompleteTableAtThePageBottomDoesNotAcquireTheNextFrame() throws {
        let fixture = try fixture(nextCaption: false, smallTable: true)
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The complete small table must retain its own region")
            return
        }

        #expect(region.continuation == nil)
        #expect(region.additionalFragments.isEmpty)
    }

    private func fixture(nextCaption: Bool, repeatedCaption: Bool = false, foreignNumber: String = "9", smallTable: Bool = false) throws -> (document: PDFDocument, annotation: PDFAnnotation, destination: PDFDestination) {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &media, nil))
        let font = try #require(NSFont(name: "Helvetica", size: 10))
        for page in 0...3 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            func text(_ value: String, _ x: CGFloat, _ y: CGFloat) {
                (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font])
            }
            func rule(_ y: CGFloat) {
                context.move(to: CGPoint(x: 72, y: y))
                context.addLine(to: CGPoint(x: 540, y: y))
                context.strokePath()
            }
            if page == 0 {
                text("See Table 8.", 40, 700)
            } else {
                text("Running header", 72, 760)
                text(String(page), 300, 25)
                let top: CGFloat = page == 1 ? (smallTable ? 140 : 670) : 720
                let bottom: CGFloat = page == 3 ? 450 : (smallTable && page == 2 ? 640 : 54)
                if page == 1 || (nextCaption || repeatedCaption) && page == 2 {
                    text("Table \(nextCaption && page == 2 ? foreignNumber : "8"): Framed data.", 72, top + 12)
                }
                rule(top)
                rule(bottom)
                for row in 0..<Int((top - bottom - 20) / 16) {
                    let y = top - 20 - CGFloat(row) * 16
                    text("\(row + 1)", 82, y)
                    text("\(page == 2 ? "middle" : "table") page row \(row + 1)", 140, y)
                }
                if page == 2 && !smallTable { text("middle page last row", 140, 60) }
                if page == 2 && smallTable { text("Table 9: A separate complete frame.", 72, bottom - 24) }
                if page == 3 {
                    text("Table \(foreignNumber): A different object.", 72, 412)
                    rule(400)
                    text("Unrelated data", 82, 380)
                    text("99", 300, 380)
                    rule(360)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let source = try #require(document.page(at: 0)), target = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try bounds("8", on: source), forType: .link, withProperties: nil)
        source.addAnnotation(annotation)
        let destination = PDFDestination(page: target, at: CGPoint(x: 72, y: 700))
        annotation.destination = destination
        return (document, annotation, destination)
    }

    private func bounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }
}

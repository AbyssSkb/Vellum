@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Native PDF table object ownership")
struct PDFReferenceObjectOwnershipTests {
    @Test(arguments: ["8", "A.1", "3b"])
    func proseReferenceDoesNotReplaceTheActualCaption(number: String) throws {
        let fixture = try makePage([
            ("Table \(number). For these configurations we compare the following experimental results.", 72, 724, 12),
            ("Model", 78, 662, 10), ("Score", 330, 662, 10),
            ("Alpha", 78, 638, 10), ("0.92", 330, 638, 10),
            ("Beta", 78, 620, 10), ("0.85", 330, 620, 10),
            ("Table \(number): Comparison under the same budget.", 72, 580, 11),
            ("The uncertainty is across repeated measurements.", 72, 566, 11),
            ("A separate body paragraph follows the object.", 72, 530, 12)
        ], ruleYs: [684, 654, 608])
        let object = try resolved(fixture, number: number, at: CGPoint(x: 72, y: 736))

        for text in ["Model", "Beta", "0.85", "Table \(number):", "The uncertainty"] {
            #expect(object.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)))
        }
        #expect(!object.bounds.intersects(try textBounds("Table \(number). For", on: fixture.page)))
        #expect(!object.bounds.intersects(try textBounds("A separate body", on: fixture.page)))
    }

    @Test(arguments: [false, true])
    func framedTextCellsContinueAcrossInternalSeparatorsWithTheCaptionFontSize(captionAbove: Bool) throws {
        let captionY: CGFloat = captionAbove ? 740 : 480
        let fixture = try makePage([
            ("Table 3: A structured example.", 72, captionY, 11),
            ("The description continues on this separate caption line.", 72, captionY - 14, 11),
            ("A final line describes the contents of the complete object.", 72, captionY - 28, 11),
            ("First block", 80, 660, 11),
            ("A short label", 80, 646, 11),
            ("This cell contains several lines of ordinary explanatory text that belong together.", 80, 612, 11),
            ("2 groups remain inside the same framed example with a shared text style.", 80, 598, 11),
            ("The final sentence completes this first text block without ending the whole table.", 80, 584, 11),
            ("Second block", 80, 552, 11),
            ("let result = transform(value)", 80, 538, 11),
            ("return result", 80, 524, 11),
            ("A separate body paragraph discusses something outside the framed example.", 72, 430, 12)
        ], ruleYs: [684, 632, 568, 508])
        let object = try resolved(fixture, number: "3", at: CGPoint(x: 72, y: captionY + 12))

        for text in ["First block", "This cell contains", "The final sentence", "2 groups", "Second block", "return result"] {
            #expect(object.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)))
        }
        let closing = try #require(fixture.rules.min(by: { $0.minY < $1.minY }))
        #expect(object.bounds.contains(closing))
        #expect(!object.bounds.intersects(try textBounds("A separate body", on: fixture.page)))
    }

    @Test
    func closerNeighborFrameDoesNotStealAnotherTablesCaption() throws {
        let fixture = try makePage([
            ("Table 4: First comparison.", 72, 732, 11),
            ("First model", 78, 698, 10), ("First score", 330, 698, 10),
            ("Alpha", 78, 678, 10), ("0.92", 330, 678, 10),
            ("Beta", 78, 660, 10), ("0.85", 330, 660, 10),
            ("Table 5: Second comparison.", 72, 628, 11),
            ("Second model", 78, 584, 10), ("Second score", 330, 584, 10),
            ("Gamma", 78, 564, 10), ("0.72", 330, 564, 10),
            ("Delta", 78, 546, 10), ("0.65", 330, 546, 10)
        ], ruleYs: [720, 690, 648, 606, 576, 534])
        let object = try resolved(fixture, number: "5", at: CGPoint(x: 72, y: 640))

        for text in ["Table 5:", "Second model", "Gamma", "Delta", "0.65"] {
            #expect(object.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)))
        }
        #expect(!object.bounds.intersects(try textBounds("First model", on: fixture.page)))
        #expect(!object.bounds.intersects(try textBounds("Alpha", on: fixture.page)))
    }

    @Test
    func wideCaptionsSeparateNarrowFramesWithTheSameRuleWidth() throws {
        let fixture = try makePage([
            ("First header", 190, 698, 10), ("Score", 330, 698, 10),
            ("Alpha", 190, 678, 10), ("0.92", 330, 678, 10),
            ("Beta", 190, 660, 10), ("0.85", 330, 660, 10),
            ("Table 4: This description extends beyond both sides of the narrow data grid.", 72, 628, 11),
            ("Second header", 190, 398, 10), ("Score", 330, 398, 10),
            ("Gamma", 190, 378, 10), ("0.72", 330, 378, 10),
            ("Delta", 190, 360, 10), ("0.65", 330, 360, 10),
            ("Table 5: Another wide description belongs to the lower narrow data grid.", 72, 328, 11)
        ], ruleYs: [720, 690, 648, 420, 390, 348], ruleX: 180, ruleWidth: 238)
        let first = try resolved(fixture, number: "4", at: CGPoint(x: 72, y: 640))
        let second = try resolved(fixture, number: "5", at: CGPoint(x: 72, y: 340))

        for text in ["First header", "Alpha", "Beta"] {
            #expect(first.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)))
            #expect(!second.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
        for text in ["Second header", "Gamma", "Delta"] {
            #expect(second.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)))
            #expect(!first.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
        #expect(first.parts.filter { $0.role == .rule }.count == 3)
        #expect(second.parts.filter { $0.role == .rule }.count == 3)
    }

    @Test
    func compactSingleLineHeaderAndSeparatedCaptionFragmentsRemainComplete() throws {
        let fixture = try makePage([
            ("First group value Second group value Third group value Fourth group value", 80, 662, 10),
            ("Alpha", 80, 638, 10), ("0.92", 330, 638, 10),
            ("Beta", 80, 620, 10), ("0.85", 330, 620, 10),
            ("Table 6:", 72, 580, 11),
            ("A comparison with several column groups.", 118, 580, 11)
        ], ruleYs: [684, 654, 608])
        let object = try resolved(fixture, number: "6", at: CGPoint(x: 72, y: 592))

        for text in ["First group", "Alpha", "Beta", "A comparison"] {
            #expect(object.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds(text, on: fixture.page)))
        }
        #expect(object.parts.filter { $0.role == .rule }.count == 3)
    }

    @Test
    func framedTextCellsMayLeaveSpaceAboveTheirClosingRule() throws {
        let fixture = try makePage([
            ("Table 7: A text cell with bottom padding.", 72, 704, 11),
            ("This framed cell contains a complete sentence with the same type size as its caption.", 80, 662, 11),
            ("Its final sentence remains part of the cell even when blank space follows the text.", 80, 648, 11)
        ], ruleYs: [684, 600])
        let object = try resolved(fixture, number: "7", at: CGPoint(x: 72, y: 716))

        #expect(object.bounds.insetBy(dx: -1, dy: -1).contains(try textBounds("Its final sentence", on: fixture.page)))
        #expect(object.parts.filter { $0.role == .rule }.count == 2)
    }

    @Test
    func completeCaptionDoesNotBridgeSameBaselineNeighboringCells() throws {
        let title = "Figure 3: A complete explanation."
        let font = try #require(NSFont(name: "Helvetica", size: 10))
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        let neighborX = 72 + width + 12
        let fixture = try makePage([
            (title, 72, 580, 10),
            ("Caption description continues.", 72, 568, 10),
            ("A final caption line.", 72, 556, 10),
            ("External row", neighborX, 580, 10),
            ("External values", neighborX, 568, 10),
            ("External total", neighborX, 556, 10)
        ], ruleYs: [])
        let lines = PDFReferenceTextLayout.lines(on: fixture.page)
        let first = try #require(lines.first { $0.text == title })
        let parts = PDFReferenceObjectLayout(lines: lines, rules: [], crop: fixture.page.bounds(for: .cropBox))
            .caption(startingAt: first.bounds, owner: CGRect(x: 72, y: 610, width: width, height: 80))
        let bounds = PDFReferenceObjectLayout.Object(parts: parts).bounds

        #expect(bounds.contains(try textBounds("A final caption line.", on: fixture.page)))
        for text in ["External row", "External values", "External total"] {
            #expect(!bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let rules: [CGRect]
    }

    private func makePage(_ content: [(String, CGFloat, CGFloat, CGFloat)], ruleYs: [CGFloat],
                          ruleX: CGFloat = 72, ruleWidth: CGFloat = 468) throws -> Fixture {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (text, x, y, size) in content {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont(name: "Helvetica", size: size)!])
        }
        NSGraphicsContext.restoreGraphicsState()
        for y in ruleYs {
            context.move(to: CGPoint(x: ruleX, y: y))
            context.addLine(to: CGPoint(x: ruleX + ruleWidth, y: y))
            context.strokePath()
        }
        context.endPDFPage()
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let page = try #require(document.page(at: 0))
        let native = try #require(page.pageRef)
        return Fixture(document: document, page: page, rules: PDFGraphicBounds.layoutRules(on: native))
    }

    private func resolved(_ fixture: Fixture, number: String, at point: CGPoint) throws -> PDFReferenceObjectLayout.Object {
        try #require(PDFReferenceObjectLayout(lines: PDFReferenceTextLayout.lines(on: fixture.page),
                                             rules: fixture.rules, crop: fixture.page.bounds(for: .cropBox))
            .object(kind: .table, number: number, near: point))
    }

    private func textBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let source = try #require(page.string) as NSString
        let range = source.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }
}

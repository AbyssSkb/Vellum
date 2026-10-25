@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reference text layout")
struct PDFReferenceTextLayoutTests {
    @Test
    func adjacentColumnsStaySeparateAndRowsHaveStableReadingOrder() throws {
        let document = try makeTextPDF(pages: [[
            ("Right caption", NSPoint(x: 350, y: 650)),
            ("Lower paragraph", NSPoint(x: 40, y: 610)),
            ("Left caption", NSPoint(x: 40, y: 650))
        ]])
        let page = try #require(document.page(at: 0))

        let lines = PDFReferenceTextLayout.lines(on: page)

        #expect(lines.map(\.text) == ["Left caption", "Right caption", "Lower paragraph"])
        #expect(lines[0].bounds.maxX < lines[1].bounds.minX)
        #expect(lines[1].bounds.minY > lines[2].bounds.maxY)
    }

    @Test
    func tableCellsAndEquationNumbersRemainIndependentSegments() throws {
        let document = try makeTextPDF(pages: [[
            ("0.1", NSPoint(x: 40, y: 600)),
            ("42", NSPoint(x: 180, y: 600)),
            ("100", NSPoint(x: 320, y: 600)),
            ("x = y + 1", NSPoint(x: 120, y: 500)),
            ("(7)", NSPoint(x: 500, y: 500))
        ]])
        let page = try #require(document.page(at: 0))

        #expect(PDFReferenceTextLayout.lines(on: page).map(\.text) == ["0.1", "42", "100", "x = y + 1", "(7)"])
    }

    @Test
    func physicalRowsStaySeparateWhenEquationLabelsChangeLogicalExtraction() throws {
        let document = try makeTextPDF(pages: [[
            ("x = y + 1", NSPoint(x: 120, y: 600)),
            ("(3a)", NSPoint(x: 500, y: 600)),
            ("z = x + y", NSPoint(x: 120, y: 520)),
            ("(3b)", NSPoint(x: 500, y: 520)),
            ("Following explanation.", NSPoint(x: 72, y: 450))
        ]])
        let page = try #require(document.page(at: 0))

        #expect(PDFReferenceTextLayout.lines(on: page).map(\.text) == [
            "x = y + 1", "(3a)", "z = x + y", "(3b)", "Following explanation."
        ])
    }

    @Test
    func ordinaryWordsAndSuperscriptsShareTheirVisualLine() throws {
        let document = try layoutDocument([
            ("m", NSPoint(x: 40, y: 600), 18),
            ("2", NSPoint(x: 55, y: 609), 10),
            ("Next line", NSPoint(x: 40, y: 570), 18)
        ])
        let page = try #require(document.page(at: 0))

        #expect(PDFReferenceTextLayout.lines(on: page).map(\.text) == ["m2", "Next line"])
    }

    @Test
    func lineTypographyRetainsTheBodySizeInsteadOfASuperscriptSize() throws {
        let document = try layoutDocument([
            ("Body text", NSPoint(x: 40, y: 600), 18),
            ("2", NSPoint(x: 124, y: 609), 10),
            ("A smaller table note.", NSPoint(x: 40, y: 570), 9)
        ])
        let page = try #require(document.page(at: 0))

        let lines = PDFReferenceTextLayout.lines(on: page)

        let body = try #require(lines.first { $0.text.hasPrefix("Body text") })
        let note = try #require(lines.first { $0.text == "A smaller table note." })
        #expect(abs(body.fontSize - 18) < 0.05)
        #expect(abs(note.fontSize - 9) < 0.05)
    }

    @Test
    func smallTextStillSeparatesAcrossANarrowColumnGutter() throws {
        let caption = "Table 2. Decoding speedup over baseline."
        let width = (caption as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
        let document = try layoutDocument([
            (caption, NSPoint(x: 40, y: 540), 10),
            ("Math500", NSPoint(x: 40 + width + 25, y: 540), 10)
        ])
        let page = try #require(document.page(at: 0))

        #expect(PDFReferenceTextLayout.lines(on: page).map(\.text) == [caption, "Math500"])
    }

    @Test
    func aTallNeighboringColumnCannotMergeConsecutiveCaptionRows() throws {
        let document = try layoutDocument([
            ("Table 2. First caption line.", NSPoint(x: 40, y: 540), 10),
            ("Second caption line.", NSPoint(x: 40, y: 530), 10),
            ("A", NSPoint(x: 400, y: 535), 24)
        ])
        let page = try #require(document.page(at: 0))

        let lines = PDFReferenceTextLayout.lines(on: page)

        let first = try #require(lines.first { $0.text == "Table 2. First caption line." }, "Segments: \(lines.map { ($0.text, $0.bounds) })")
        let second = try #require(lines.first { $0.text == "Second caption line." })
        #expect(first.bounds.midY > second.bounds.midY)
        #expect(first.bounds.maxX < 350)
        #expect(second.bounds.maxX < 350)
        #expect(lines.contains { $0.text == "A" })
    }

    @Test(arguments: [0, 90, 180, 270])
    func cropOriginsAndRotationKeepRawPageCoordinates(rotation: Int) throws {
        let document = try makeTextPDF(pages: [[
            ("Outside above", NSPoint(x: 20, y: 730)),
            ("Inside first", NSPoint(x: 130, y: 600)),
            ("Inside second", NSPoint(x: 130, y: 570)),
            ("Outside below", NSPoint(x: 130, y: 110))
        ]])
        let page = try #require(document.page(at: 0))
        let expected = try #require(PDFReferenceTextLayout.lines(on: page).first { $0.text == "Inside first" }).bounds
        let crop = CGRect(x: 100, y: 150, width: 360, height: 500)
        page.setBounds(crop, for: .cropBox)
        page.rotation = rotation

        let lines = PDFReferenceTextLayout.lines(on: page)

        #expect(lines.map(\.text) == ["Inside first", "Inside second"])
        let first = try #require(lines.first)
        #expect(abs(first.bounds.minX - expected.minX) < 0.05)
        #expect(abs(first.bounds.minY - expected.minY) < 0.05)
        #expect(abs(first.bounds.maxX - expected.maxX) < 0.05)
        #expect(abs(first.bounds.maxY - expected.maxY) < 0.05)
        #expect(lines.allSatisfy { crop.contains($0.bounds) })
    }

    private func layoutDocument(_ runs: [(String, NSPoint, CGFloat)]) throws -> PDFDocument {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &media, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (text, point, size) in runs {
            (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size)])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }
}

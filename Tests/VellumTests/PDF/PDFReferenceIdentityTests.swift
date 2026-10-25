@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Reference identity and missing coordinates")
struct PDFReferenceIdentityTests {
    @Test(arguments: ["and", ",", "&"])
    func everyExplicitTableInASequenceRetainsItsIdentity(separator: String) throws {
        let fixture = try fixture(source: "Tables 2 \(separator) 3 compare the results.", linked: "3", name: "table.99", content: """
        BT /F1 12 Tf 72 650 Td (Table 3: Comparison.) Tj
        0 -30 Td (Method    Score) Tj
        0 -18 Td (Alpha       0.91) Tj
        0 -18 Td (Beta        0.88) Tj
        0 -70 Td (Unrelated following text.) Tj ET
        72 636 m 280 636 l S 72 568 m 280 568 l S
        """, point: CGPoint(x: 72, y: 664))

        let region = try resolved(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Table 3")
        #expect(region.bounds.contains(try bounds("Table 3: Comparison.", on: fixture.page)))
        #expect(region.bounds.contains(try bounds("Beta", on: fixture.page)))
        #expect(!region.bounds.intersects(try bounds("Unrelated following", on: fixture.page)))
    }

    @Test(arguments: [CGPoint(x: CGFloat.infinity, y: CGFloat.infinity), CGPoint(x: CGFloat.infinity, y: 576)])
    func missingCoordinatesFindTheUniqueExplicitBibliographyNumber(point: CGPoint) throws {
        let fixture = try fixture(source: "See [2] for details.", linked: "2", name: "cite.opaque-key", content: """
        BT /F1 12 Tf 72 650 Td (References) Tj
        0 -40 Td ([1] A. Writer. Earlier work, 2020.) Tj
        12 -16 Td (A continuation for the earlier work.) Tj
        -12 -32 Td ([2] B. Author. The intended publication, 2021.) Tj
        12 -16 Td (Conference proceedings and complete address.) Tj
        -12 -32 Td ([3] C. Researcher. A later work, 2022.) Tj ET
        """, point: point)

        let region = try resolved(fixture)

        #expect(region.bounds.contains(try bounds("[2] B. Author.", on: fixture.page)))
        #expect(region.bounds.contains(try bounds("Conference proceedings", on: fixture.page)))
        #expect(!region.bounds.intersects(try bounds("[1] A. Writer.", on: fixture.page)))
        #expect(!region.bounds.intersects(try bounds("[3] C. Researcher.", on: fixture.page)))
        #expect(region.destination?.page === fixture.page)
        #expect(region.destination?.point == CGPoint(x: region.bounds.minX, y: region.bounds.maxY))
    }

    @Test
    func missingCoordinatesUseAnExplicitAuthorAndYearTogether() throws {
        let fixture = try fixture(source: "Following Morgan et al. (2021).", linked: "2021", name: "cite.arbitrary", content: """
        BT /F1 12 Tf 72 650 Td (Morgan, Alex and collaborators.) Tj
        12 -16 Td (A different publication, 2020.) Tj
        -12 -32 Td (Morgan, Alex and collaborators.) Tj
        12 -16 Td (The intended publication, 2021.) Tj
        0 -16 Td (Complete venue and address.) Tj
        -12 -32 Td (Other, Author. Unrelated work, 2021.) Tj
        12 -16 Td (Its own continuation.) Tj ET
        """, point: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity))

        let region = try resolved(fixture)

        #expect(region.bounds.contains(try bounds("The intended publication", on: fixture.page)))
        #expect(region.bounds.contains(try bounds("Complete venue", on: fixture.page)))
        #expect(!region.bounds.intersects(try bounds("A different publication", on: fixture.page)))
        #expect(!region.bounds.intersects(try bounds("Other, Author.", on: fixture.page)))
    }

    @Test
    func ambiguousAuthorAndYearDoNotGuessABibliographyEntry() throws {
        let fixture = try fixture(source: "Following Morgan et al. (2021).", linked: "2021", name: "cite.arbitrary", content: """
        BT /F1 12 Tf 72 650 Td (Morgan, Alex and collaborators.) Tj
        12 -16 Td (One publication, 2021.) Tj
        -12 -32 Td (Morgan, Alex and collaborators.) Tj
        12 -16 Td (Another publication, 2021.) Tj ET
        """, point: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("Missing coordinates require a unique explicit identity")
            return
        }
    }

    @Test(arguments: ["Hfootnote.2", "Hfootnote.7"])
    func namedFootnotesIncludeTheWholeNoteWithoutOtherNotesOrBodyText(name: String) throws {
        let fixture = try fixture(source: "A claim needs evidence 2.", linked: "2", name: name, content: """
        BT /F1 12 Tf 72 220 Td (The main body is unrelated to the footnote.) Tj ET
        72 180 m 210 180 l S
        BT /F1 9 Tf 72 160 Td (1 The preceding note.) Tj
        0 -26 Td (2 The intended explanatory note starts here.) Tj
        6 -13 Td (Its complete continuation stays in the preview.) Tj
        -6 -26 Td (3 A separate following note.) Tj ET
        """, point: CGPoint(x: 72, y: 146))

        let region = try resolved(fixture)

        #expect(region.bounds.contains(try bounds("2 The intended", on: fixture.page)))
        #expect(region.bounds.contains(try bounds("Its complete continuation", on: fixture.page)))
        for text in ["The main body", "1 The preceding", "3 A separate"] {
            #expect(!region.bounds.intersects(try bounds(text, on: fixture.page)))
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func fixture(source: String, linked: String, name: String? = nil, content: String, point: CGPoint) throws -> Fixture {
        let escaped = source.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        let sourceStream = "BT /F1 12 Tf 40 700 Td (\(escaped)) Tj ET"
        let coordinate = "\(point.x.isFinite ? String(describing: point.x) : "null") \(point.y.isFinite ? String(describing: point.y) : "null")"
        let destination = "[5 0 R /XYZ \(coordinate) null]"
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R \(name.map { "/Names << /Dests << /Names [(\($0)) \(destination)] >> >>" } ?? "") >>",
            "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(sourceStream.utf8.count) >>\nstream\n\(sourceStream)\nendstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        ]
        func document(_ objects: [String]) throws -> PDFDocument {
            var pdf = "%PDF-1.7\n", offsets = [0]
            for (index, object) in objects.enumerated() {
                offsets.append(pdf.utf8.count)
                pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
            }
            let xref = pdf.utf8.count
            pdf += "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
            for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
            pdf += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF"
            return try #require(PDFDocument(data: Data(pdf.utf8)))
        }
        let first = try document(objects)
        let annotationBounds = try bounds(linked, on: #require(first.page(at: 0)))
        objects[2] = objects[2].replacingOccurrences(of: "/Contents 4 0 R", with: "/Contents 4 0 R /Annots [8 0 R]")
        objects.append("<< /Type /Annot /Subtype /Link /Rect [\(annotationBounds.minX) \(annotationBounds.minY) \(annotationBounds.maxX) \(annotationBounds.maxY)] /Dest \(name.map { "(\($0))" } ?? destination) >>")
        let pdf = try document(objects)
        let sourcePage = try #require(pdf.page(at: 0)), page = try #require(pdf.page(at: 1))
        return Fixture(document: pdf, page: page, annotation: try #require(sourcePage.annotations.first),
                       destination: PDFDestination(page: page, at: point))
    }

    private func bounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private func resolved(_ fixture: Fixture) throws -> PDFReferencePreview.Region {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("An explicit reference must produce its intended object crop")
            throw MissingRegion()
        }
        return region
    }

    private struct MissingRegion: Error {}
}

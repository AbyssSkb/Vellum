@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Bibliography reference previews")
struct PDFBibliographyPreviewTests {
    @Test(arguments: ["[77]", "77."])
    func numberedEntriesIncludeSeparateLabelsAndAllContinuationLines(marker: String) throws {
        let fixture = try makeFixture(source: "Earlier work (Olsson et al., 2022).", linked: "2022", lines: [
            ("Previous publication ends in 2021.", NSPoint(x: 110, y: 624)),
            (marker, NSPoint(x: 72, y: 600)),
            ("Catherine Writer. A study of context.", NSPoint(x: 110, y: 600)),
            ("In: Conference 2022, pp. 1-8.", NSPoint(x: 110, y: 576)),
            ("[78] Next Author. Another work, 2023.", NSPoint(x: 72, y: 552)),
            ("Its continuation is unrelated.", NSPoint(x: 110, y: 528)),
            ("Right column, 2022.", NSPoint(x: 450, y: 600))
        ], first: marker)

        let bounds = try resolvedBounds(fixture)

        for text in [marker, "Catherine Writer.", "In: Conference 2022, pp. 1-8."] {
            #expect(bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["Previous publication", "[78]", "Its continuation", "Right column"] {
            #expect(!bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test
    func theFirstNumberedEntryExcludesTheReferencesHeading() throws {
        let fixture = try makeFixture(source: "See [1].", linked: "1", lines: [
            ("References", NSPoint(x: 72, y: 632)),
            ("[1] Martin Writer. Unitary networks.", NSPoint(x: 72, y: 600)),
            ("Conference on Learning, 2016, pp. 1-8.", NSPoint(x: 110, y: 576))
        ], first: "[1] Martin Writer.")

        let bounds = try resolvedBounds(fixture)

        #expect(bounds.contains(try textBounds("[1] Martin Writer.", on: fixture.page)))
        #expect(bounds.contains(try textBounds("Conference on Learning", on: fixture.page)))
        #expect(!bounds.intersects(try textBounds("References", on: fixture.page)))
    }

    @Test
    func aNarrowColumnGutterDoesNotJoinAdjacentEntries() throws {
        let first = "[1] Left Author. A publication, 2022."
        let width = (first as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
        let fixture = try makeFixture(source: "See [1].", linked: "1", lines: [
            (first, NSPoint(x: 40, y: 600)),
            ("Its complete continuation.", NSPoint(x: 55, y: 586)),
            ("[2] Right Author. Another publication, 2023.", NSPoint(x: 40 + width + 25, y: 600)),
            ("Right continuation.", NSPoint(x: 55 + width + 25, y: 586))
        ], first: first, fontSize: 10)

        let bounds = try resolvedBounds(fixture)

        #expect(bounds.contains(try textBounds(first, on: fixture.page)))
        #expect(bounds.contains(try textBounds("Its complete continuation.", on: fixture.page)))
        #expect(!bounds.intersects(try textBounds("[2] Right Author.", on: fixture.page)))
        #expect(!bounds.intersects(try textBounds("Right continuation.", on: fixture.page)))
    }

    @Test(arguments: ["Houlsby et al. (2019)", "Brown et al. (2020)"])
    func hangingEntriesIncludeIndentedContinuationsWithoutNeighboringPublications(source: String) throws {
        let fixture = try makeFixture(source: source, linked: "et al.", lines: [
            ("Previous Author. A paper, 2018.", NSPoint(x: 72, y: 624)),
            ("Neil Writer, Andrei Author, and colleagues.", NSPoint(x: 72, y: 600)),
            ("Parameter efficient transfer learning.", NSPoint(x: 84, y: 576)),
            ("Conference 2019. URL arxiv.org/1234.", NSPoint(x: 84, y: 552)),
            ("00751.", NSPoint(x: 84, y: 528)),
            ("Max Author. Another publication, 2021.", NSPoint(x: 72, y: 504)),
            ("Its continuation is unrelated.", NSPoint(x: 84, y: 480)),
            ("Right column, 2019.", NSPoint(x: 450, y: 576))
        ], first: "Neil Writer,")

        let bounds = try resolvedBounds(fixture)

        for text in ["Neil Writer,", "Parameter efficient", "Conference 2019.", "00751."] {
            #expect(bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["Previous Author", "Max Author", "Its continuation", "Right column"] {
            #expect(!bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test(arguments: ["Radford et al.", "b"])
    func letterOnlyCitationsIncludeTheMatchingUndatedEntry(linked: String) throws {
        let fixture = try makeFixture(source: "Earlier work (Radford et al., b; Brown et al., 2020).", linked: linked, lines: [
            ("Alec Radford and previous colleagues.", NSPoint(x: 72, y: 648)),
            ("An earlier language model. pp. 12, a.", NSPoint(x: 84, y: 624)),
            ("Alec Radford, Jeffrey Writer, and colleagues.", NSPoint(x: 72, y: 600)),
            ("Language models are multitask learners. pp. 24, b.", NSPoint(x: 84, y: 576)),
            ("Pranav Author. The next publication, 2018.", NSPoint(x: 72, y: 552)),
            ("Its continuation is unrelated.", NSPoint(x: 84, y: 528))
        ], first: "Alec Radford, Jeffrey")

        let bounds = try resolvedBounds(fixture)

        for text in ["Alec Radford, Jeffrey", "Language models are multitask learners."] {
            #expect(bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["Alec Radford and previous", "An earlier language model.", "Pranav Author", "Its continuation"] {
            #expect(!bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test(arguments: ["Morgan et al.", "n.d."])
    func citationsWithoutADateRetainTheirCompleteEntry(linked: String) throws {
        let fixture = try makeFixture(source: "See Morgan et al. (n.d.).", linked: linked, lines: [
            ("Alex Morgan and several collaborators.", NSPoint(x: 72, y: 600)),
            ("A publication with no date. URL example.org/paper.", NSPoint(x: 84, y: 576)),
            ("Next Author. Another publication, 2021.", NSPoint(x: 72, y: 552))
        ], first: "Alex Morgan")

        let bounds = try resolvedBounds(fixture)

        #expect(bounds.contains(try textBounds("Alex Morgan", on: fixture.page)))
        #expect(bounds.contains(try textBounds("A publication with no date.", on: fixture.page)))
        #expect(!bounds.intersects(try textBounds("Next Author", on: fixture.page)))
    }

    @Test
    func anUndatedCitationDoesNotTreatAnUnrelatedParagraphAsABibliographyEntry() throws {
        let fixture = try makeFixture(source: "See Morgan et al. (n.d.).", linked: "Morgan et al.", lines: [
            ("This unrelated paragraph mentions collaborators.", NSPoint(x: 72, y: 600)),
            ("Its indented continuation has no date.", NSPoint(x: 84, y: 576)),
            ("A separate ordinary paragraph follows.", NSPoint(x: 72, y: 552))
        ], first: "This unrelated paragraph")

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("An undated citation must match its bibliography author")
            return
        }
    }

    @Test(arguments: ["(cite.publication)", "/cite.publication"], [false, true])
    func embeddedCitationDestinationsRecognizeSplitAuthorFragments(destination: String, action: Bool) throws {
        let fixture = try makeNamedCitationFixture(destination: destination, action: action)

        let bounds = try resolvedBounds(fixture)

        #expect(bounds.contains(try textBounds("Karen Hambardzumyan", on: fixture.page)))
        #expect(bounds.contains(try textBounds("Complete paper title, 2020.", on: fixture.page)))
        #expect(!bounds.intersects(try textBounds("Next Author", on: fixture.page)))
    }

    @Test(arguments: ["(cite.publication)", "/cite.publication"], [false, true])
    func narrativeCitationAuthorAndParenthesizedYearKeepTheSameNamedEntry(destination: String, action: Bool) throws {
        let fixture = try makeNamedCitationFixture(destination: destination, action: action,
            source: #"BT /F1 12 Tf 40 700 Td (Following ) Tj 56 0 Td (Dai et al.) Tj 50 0 Td (\(2024\)) Tj ET"#,
            target: "BT /F1 12 Tf 72 624 Td (Previous Author. Earlier work, 2023.) Tj 0 -24 Td (Damai Dai and colleagues.) Tj 12 -16 Td (Complete paper title, 2024.) Tj -12 -24 Td (Next Author. Another paper, 2025.) Tj ET",
            annotationRects: ["96 697 144 714", "150 697 176 714"])
        let sourcePage = try #require(fixture.document.page(at: 0))
        let annotations = sourcePage.annotations
        try #require(annotations.count == 2)
        #expect(sourcePage.selection(for: annotations[0].bounds)?.string == "Dai et al.")
        #expect(sourcePage.selection(for: annotations[1].bounds)?.string == "2024")
        var resolved: [CGRect] = []
        for annotation in annotations {
            guard case .region(let region) = PDFReferencePreview.resolve(for: annotation, destination: fixture.destination) else {
                Issue.record("Both parts of a named citation must resolve to the bibliography entry")
                continue
            }
            #expect(region.title == nil)
            #expect(region.bounds.contains(try textBounds("Damai Dai and colleagues.", on: fixture.page)))
            #expect(region.bounds.contains(try textBounds("Complete paper title, 2024.", on: fixture.page)))
            #expect(!region.bounds.intersects(try textBounds("Previous Author", on: fixture.page)))
            #expect(!region.bounds.intersects(try textBounds("Next Author", on: fixture.page)))
            resolved.append(region.bounds)
        }
        #expect(resolved.count == 2)
        #expect(resolved.first == resolved.last)
    }

    @Test
    func aNamedCitationWithAParenthesizedNumberIsNotAnEquation() throws {
        let fixture = try makeNamedCitationFixture(destination: "(cite.publication)", action: true,
            source: #"BT /F1 12 Tf 40 700 Td (See \(2\).) Tj ET"#,
            target: "BT /F1 12 Tf 72 600 Td ([2] Damai Dai and colleagues.) Tj 12 -16 Td (Complete paper title, 2024.) Tj -12 -24 Td ([3] Next Author. Another paper, 2025.) Tj ET",
            annotationRects: ["69 697 75 714"])

        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The embedded citation identity must take precedence over equation-shaped text")
            return
        }
        #expect(region.title == nil)
        #expect(region.bounds.contains(try textBounds("[2] Damai Dai", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("Complete paper title, 2024.", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("[3] Next Author", on: fixture.page)))
    }

    @Test(arguments: ["(section.publication)", "/section.publication"])
    func otherNamedDestinationsDoNotTurnAuthorFragmentsIntoCitations(destination: String) throws {
        let fixture = try makeNamedCitationFixture(destination: destination, action: true)

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("Only embedded citation destinations identify a citation")
            return
        }
    }

    @Test
    func ordinaryIndentedParagraphsKeepTheirExistingGrouping() throws {
        let fixture = try makeFixture(source: "See this discussion.", linked: "discussion", lines: [
            ("The discussion starts in 2022.", NSPoint(x: 72, y: 600)),
            ("An indented line follows here.", NSPoint(x: 84, y: 576)),
            ("Its continuation stays indented.", NSPoint(x: 84, y: 552))
        ], first: "The discussion")

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A non-citation must retain the ordinary paragraph fallback")
            return
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func makeFixture(source: String, linked: String, lines: [(String, NSPoint)], first: String, fontSize: CGFloat = 18) throws -> Fixture {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for pageLines in [[(source, NSPoint(x: 40, y: 700))], lines] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (text, point) in pageLines {
                (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)])
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let sourcePage = try #require(document.page(at: 0))
        let page = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try textBounds(linked, on: sourcePage), forType: .link, withProperties: nil)
        sourcePage.addAnnotation(annotation)
        let start = try textBounds(first, on: page)
        let destination = PDFDestination(page: page, at: CGPoint(x: start.minX - 24, y: start.maxY + 4))
        annotation.destination = destination
        return Fixture(document: document, page: page, annotation: annotation, destination: destination)
    }

    private func resolvedBounds(_ fixture: Fixture) throws -> CGRect {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A citation should resolve to its complete bibliography entry")
            throw MissingRegion()
        }
        return region.bounds
    }

    private func makeNamedCitationFixture(destination: String, action: Bool,
        source: String = "BT /F1 12 Tf 40 700 Td (Ham-) Tj 0 -16 Td (bardzumyan et al., 2020) Tj ET",
        target: String = "BT /F1 12 Tf 72 600 Td (Karen Hambardzumyan and colleagues.) Tj 12 -16 Td (Complete paper title, 2020.) Tj -12 -24 Td (Next Author. Another paper, 2021.) Tj ET",
        annotationRects: [String] = ["40 697 70 714"]) throws -> Fixture {
        let key = destination.contains("cite.") ? "cite.publication" : "section.publication"
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R /Dests << /\(key) [5 0 R /XYZ 48 616 null] >> /Names << /Dests << /Names [(\(key)) [5 0 R /XYZ 48 616 null]] >> >> >>",
            "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R /Annots [\(annotationRects.indices.map { "\($0 + 8) 0 R" }.joined(separator: " "))] >>",
            "<< /Length \(source.utf8.count) >>\nstream\n\(source)\nendstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
            "<< /Length \(target.utf8.count) >>\nstream\n\(target)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        ]
        objects += annotationRects.map { "<< /Type /Annot /Subtype /Link /Rect [\($0)] \(action ? "/A << /S /GoTo /D \(destination) >>" : "/Dest \(destination)") >>" }
        var pdf = "%PDF-1.7\n", offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF"
        let document = try #require(PDFDocument(data: Data(pdf.utf8)))
        let sourcePage = try #require(document.page(at: 0)), page = try #require(document.page(at: 1))
        let annotation = try #require(sourcePage.annotations.first)
        // PDFKit leaves name-valued destinations unresolved; classification still uses their original identity.
        let targetDestination = PDFDestination(page: page, at: CGPoint(x: 48, y: 616))
        return Fixture(document: document, page: page, annotation: annotation, destination: targetDestination)
    }

    private func textBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private struct MissingRegion: Error {}
}

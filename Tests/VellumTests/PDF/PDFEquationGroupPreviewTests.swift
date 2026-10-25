@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF grouped equation preview")
struct PDFEquationGroupPreviewTests {
    @Test(arguments: ["2", "A.1"])
    func anUnsuffixedReferenceIncludesItsMembersAndExcludesOtherEquations(number: String) throws {
        let fixture = try makeFixture(number: number)

        let region = try resolvedRegion(fixture)

        for text in ["a + b", "--------", "c + d", "(\(number)a)", "z = x + y", "(\(number)b)"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["u = v (1a)", "w = t (3a)", "The preceding explanation.", "The following explanation."] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
        #expect(region.title.map { AppUILanguage.english.text($0) } == "Equation \(number)")
    }

    @Test(arguments: ["2a", "2b", "A.1a", "A.1b"])
    func anExplicitMemberStillIncludesOnlyThatFormula(number: String) throws {
        let base = String(number.dropLast())
        let fixture = try makeFixture(number: number, base: base)

        let region = try resolvedRegion(fixture)

        let first = number.hasSuffix("a")
        for text in first ? ["a + b", "--------", "c + d", "(\(base)a)"] : ["z = x + y", "(\(base)b)"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in first ? ["z = x + y", "(\(base)b)"] : ["a + b", "(\(base)a)"] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test
    func anExactUnsuffixedLabelTakesPrecedenceOverItsLetteredMembers() throws {
        let fixture = try makeFixture(number: "2", extra: [
            ("q = r + s", NSPoint(x: 260, y: 400)),
            ("(2)", NSPoint(x: 400, y: 400))
        ])

        let region = try resolvedRegion(fixture)

        for text in ["q = r + s", "(2)"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["a + b", "(2a)", "z = x + y", "(2b)"] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func makeFixture(number: String, base: String? = nil, extra: [(String, NSPoint)] = []) throws -> Fixture {
        let base = base ?? number
        let document = try makeTextPDF(pages: [[("See Equation (\(number)).", NSPoint(x: 40, y: 650))], [
            ("The preceding explanation.", NSPoint(x: 72, y: 660)),
            ("a + b", NSPoint(x: 260, y: 600)),
            ("--------", NSPoint(x: 255, y: 588)),
            ("c + d", NSPoint(x: 260, y: 576)),
            ("(\(base)a)", NSPoint(x: 400, y: 588)),
            ("u = v (1a)", NSPoint(x: 72, y: 588)),
            ("w = t (3a)", NSPoint(x: 500, y: 588)),
            ("z = x + y", NSPoint(x: 260, y: 520)),
            ("(\(base)b)", NSPoint(x: 400, y: 520)),
            ("The following explanation.", NSPoint(x: 72, y: 450))
        ] + extra])
        let source = try #require(document.page(at: 0))
        let page = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try textBounds(number, on: source), forType: .link, withProperties: nil)
        source.addAnnotation(annotation)
        let destination = PDFDestination(page: page, at: NSPoint(x: 400, y: 600))
        annotation.destination = destination
        return Fixture(document: document, page: page, annotation: annotation, destination: destination)
    }

    private func resolvedRegion(_ fixture: Fixture) throws -> PDFReferencePreview.Region {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The equation reference should resolve to its matching formula or group")
            throw MissingRegion()
        }
        return region
    }

    private func textBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private struct MissingRegion: Error {}
}

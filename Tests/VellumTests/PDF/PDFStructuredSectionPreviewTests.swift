import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite(.serialized)
@MainActor
struct PDFStructuredSectionPreviewTests {
    @Test(arguments: [false, true])
    func aColonIntroducesACompleteFormattedListAcrossAPageBreak(colonBeforeBreak: Bool) throws {
        let first = [
            ("2. Evaluation", 72.0, 130.0, true),
            (colonBeforeBreak ? "Our benchmarks are grouped as follows:" : "Our benchmarks are grouped", 72, 106, false),
            ("2", 300, 40, false)
        ]
        let next = (colonBeforeBreak ? [] : [("into the following categories:", 72.0, 700.0, false)]) + [
            ("Language tasks", 88.0, 668.0, true),
            ("include complete reading and reasoning datasets.", 72, 652, false),
            ("Mathematics tasks", 88, 628, true),
            ("include all supported arithmetic benchmarks.", 72, 612, false),
            ("An independent paragraph follows the list.", 88, 588, false),
            ("Its remaining prose must stay outside the preview.", 72, 572, false),
            ("3. Results", 72, 532, true)
        ]
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [first, next], point: CGPoint(x: 72, y: 145))
        let region = try resolved(fixture)
        let continuation = try #require(region.continuation)
        let nextPage = try #require(fixture.document.page(at: 2))

        #expect(continuation.page === nextPage)
        for text in ["Language tasks", "include complete", "Mathematics tasks", "include all supported"] {
            #expect(continuation.bounds.contains(try bounds(text, on: nextPage)))
        }
        for text in ["An independent paragraph", "Its remaining prose", "3. Results"] {
            #expect(!continuation.bounds.intersects(try bounds(text, on: nextPage)))
        }
    }

    @Test
    func aFormattedListIncludesItsWrappedRowsOnTheSamePage() throws {
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [[
            ("2. Evaluation", 72, 700, true),
            ("The categories are:", 72, 676, false),
            ("Language tasks", 88, 652, true),
            ("include complete reading and reasoning datasets.", 72, 636, false),
            ("Mathematics tasks", 88, 612, true),
            ("include all supported arithmetic benchmarks.", 72, 596, false),
            ("An independent paragraph follows the list.", 88, 572, false),
            ("Its remaining prose must stay outside the preview.", 72, 556, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        for text in ["Language tasks", "include complete", "Mathematics tasks", "include all supported"] {
            #expect(region.bounds.contains(try bounds(text, on: page)))
        }
        #expect(!region.bounds.intersects(try bounds("An independent paragraph", on: page)))
    }

    @Test
    func aFormattedListKeepsAWholeHangingLineAcrossPagesWithoutTheNextColumn() throws {
        let longItem = "Language tasks cover the complete collection of datasets"
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [[
            ("2. Evaluation", 72, 130, true),
            ("The categories are:", 72, 106, false),
            ("2", 300, 40, false)
        ], [
            (longItem, 88, 700, true),
            ("with complete reading and reasoning coverage.", 72, 684, false),
            ("Mathematics tasks", 88, 660, true),
            ("include all supported arithmetic benchmarks.", 72, 644, false),
            ("An independent paragraph follows the list.", 88, 620, false),
            ("Right column content is independent.", 480, 700, false),
            ("Its continuation belongs in the next column.", 480, 684, false)
        ]], point: CGPoint(x: 72, y: 145))
        let region = try resolved(fixture)
        let continuation = try #require(region.continuation)
        let page = try #require(fixture.document.page(at: 2))
        let hanging = try bounds(longItem, on: page)

        #expect(continuation.page === page)
        #expect(hanging.maxX > (try bounds("with complete reading and reasoning coverage.", on: page)).maxX + 8)
        #expect(continuation.bounds.contains(hanging))
        #expect(continuation.bounds.contains(try bounds("include all supported", on: page)))
        #expect(!continuation.bounds.intersects(try bounds("An independent paragraph", on: page)))
        #expect(!continuation.bounds.intersects(try bounds("Right column content", on: page)))
    }

    @Test
    func aHangingHeadingStopsAdditionalListRowsEvenWhenTheHeadingExceedsTheColumn() throws {
        let heading = "3. The subsequent section has a heading wider than the original text column"
        let following = "Following category has a long emphasized line in the subsequent section"
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [[
            ("2. Evaluation", 72, 130, true),
            ("The categories are:", 72, 106, false),
            ("2", 300, 40, false)
        ], [
            ("First category", 88, 700, true),
            ("Its complete description stays together.", 72, 684, false),
            (heading, 88, 660, true),
            (following, 88, 636, true),
            ("The new section must remain outside.", 72, 620, false)
        ]], point: CGPoint(x: 72, y: 145))
        let region = try resolved(fixture)
        let continuation = try #require(region.continuation)
        let page = try #require(fixture.document.page(at: 2))

        #expect(continuation.bounds.contains(try bounds("First category", on: page)))
        #expect(continuation.bounds.contains(try bounds("Its complete description", on: page)))
        #expect(!continuation.bounds.intersects(try bounds(heading, on: page)))
        #expect(!continuation.bounds.intersects(try bounds(following, on: page)))
    }

    @Test
    func aColonPreservesTheExistingFormulaBlockAndItsWhereParagraph() throws {
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [[
            ("2. Method", 72, 700, true),
            ("The complete expressions are:", 72, 676, false),
            ("A = B + C", 120, 648, true),
            ("D = E + F", 180, 624, false),
            ("where all quantities retain their full context.", 72, 596, false),
            ("Both definitions remain applicable.", 72, 580, false),
            ("A separate paragraph follows here.", 88, 548, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        for text in ["A = B + C", "D = E + F", "where all quantities", "Both definitions"] {
            #expect(region.bounds.contains(try bounds(text, on: page)))
        }
        #expect(!region.bounds.intersects(try bounds("A separate paragraph", on: page)))
    }

    @Test
    func aColonPreservesAnIndentedCategoryBlockWithMixedEmphasis() throws {
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [[
            ("2. Categories", 72, 700, true),
            ("The supported categories are classified into the following complete groups:", 72, 676, false),
            ("Code agent: the complete first category.", 88, 648, true),
            ("Vision agent: another complete category.", 88, 624, false),
            ("Language agent: the final complete category.", 88, 600, false),
            ("A separate paragraph follows here.", 72, 564, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        for text in ["Code agent:", "Vision agent:", "Language agent:"] {
            #expect(region.bounds.contains(try bounds(text, on: page)))
        }
        #expect(!region.bounds.intersects(try bounds("A separate paragraph", on: page)))
    }

    @Test(arguments: ["3. Results", "B. Results", "Distant category", "• Distant item"])
    func aColonDoesNotCaptureARealHeadingOrADistantBlock(next: String) throws {
        let distant = next.contains("Distant")
        let fixture = try fixture(source: "See Section 2.", linked: "2", pages: [[
            ("2. Evaluation", 72, 700, true),
            ("The opening paragraph introduces this context:", 72, 676, false),
            (next, 88, distant ? 500 : 652, true),
            ("Independent content must remain outside.", 72, distant ? 484 : 636, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        #expect(region.bounds.contains(try bounds("The opening paragraph", on: page)))
        #expect(!region.bounds.intersects(try bounds(next, on: page)))
        #expect(!region.bounds.intersects(try bounds("Independent content", on: page)))
    }

    @Test
    func compactAlignedColumnsKeepInitialsAndDoNotSliceTheirNeighbor() throws {
        let fixture = try fixture(source: "See Appendix A.", linked: "A", pages: [[
            ("A. Contributors", 72, 700, true),
            ("Research and engineering", 72, 676, true),
            ("Alice Green", 72, 660, false), ("Ryan Black", 306, 676, false),
            ("Bing White", 72, 644, false), ("Sam Brown", 306, 660, false),
            ("H. Zhang", 72, 628, false), ("T. Smith", 306, 644, false),
            ("June Gray", 72, 612, false), ("Yuki Blue", 306, 628, false),
            ("Ming Chen", 72, 596, false), ("Zhen Gold", 306, 612, false),
            ("B. Additional Results", 72, 548, true),
            ("An independent section follows here.", 72, 524, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        for text in ["Alice Green", "H. Zhang", "Ming Chen", "Ryan Black", "T. Smith", "Zhen Gold"] {
            #expect(region.bounds.contains(try bounds(text, on: page)))
        }
        #expect(!region.bounds.intersects(try bounds("B. Additional Results", on: page)))
    }

    @Test
    func aCompactRoleListStopsAtTheNextRoleBeforeReadingTheFollowingColumn() throws {
        let fixture = try fixture(source: "See Appendix A.", linked: "A", pages: [[
            ("A. Contributors", 72, 188, true),
            ("Research and engineering", 72, 164, true),
            ("Alice Green", 72, 148, false), ("Ryan Black", 306, 164, false),
            ("Bing White", 72, 132, false), ("Sam Brown", 306, 148, false),
            ("H. Zhang", 72, 116, false), ("T. Smith", 306, 132, false),
            ("June Gray", 72, 100, false), ("Yuki Blue", 306, 116, false),
            ("Ming Chen", 72, 84, false), ("Zhen Gold", 306, 100, false),
            ("2", 300, 40, false)
        ], [
            ("Ning White", 72, 700, false), ("Xiao Brown", 306, 700, false),
            ("Pei Chen", 72, 684, false), ("Yuan Gray", 306, 684, false),
            ("Qi Green", 72, 668, false),
            ("R. Smith", 72, 652, false),
            ("Business and compliance", 306, 660, true),
            ("Business contributor", 306, 644, false),
            ("Data annotation", 72, 620, true),
            ("Annotation contributor", 72, 604, false)
        ]], point: CGPoint(x: 72, y: 202))
        let region = try resolved(fixture)
        let continuation = try #require(region.continuation)
        let nextPage = try #require(fixture.document.page(at: 2))

        #expect(continuation.page === nextPage)
        for text in ["Ning White", "R. Smith"] {
            #expect(continuation.bounds.contains(try bounds(text, on: nextPage)))
        }
        for text in ["Xiao Brown", "Yuan Gray", "Business and compliance", "Business contributor", "Data annotation", "Annotation contributor"] {
            #expect(!continuation.bounds.intersects(try bounds(text, on: nextPage)))
        }
    }

    @Test
    func anAlphabeticHeadingAfterOrdinaryProseIsStillABoundary() throws {
        let fixture = try fixture(source: "See Appendix A.", linked: "A", pages: [[
            ("A. Method", 72, 700, true),
            ("The opening paragraph remains together.", 72, 676, false),
            ("Its final line provides enough context.", 72, 660, false),
            ("B. Results", 72, 644, false),
            ("A separate section starts here.", 72, 628, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        #expect(region.bounds.contains(try bounds("Its final line", on: page)))
        #expect(!region.bounds.intersects(try bounds("B. Results", on: page)))
    }

    @Test(arguments: ["Tables 2-5", "Tables 2–5", "Tables 2—5"])
    func aRangeEndpointKeepsTheExplicitObjectKind(reference: String) throws {
        let fixture = try fixture(source: "See \(reference) for the results.", linked: "5", pages: [[
            ("Table 5: Results.", 72, 700, false),
            ("Model", 72, 676, false), ("Train", 170, 676, false), ("Test", 260, 676, false),
            ("Alpha", 72, 660, false), ("0.91", 170, 660, false), ("0.88", 260, 660, false),
            ("Beta", 72, 644, false), ("0.72", 170, 644, false), ("0.69", 260, 644, false),
            ("Unrelated prose follows the table.", 72, 580, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)
        let page = try #require(fixture.document.page(at: 1))

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Table 5")
        #expect(region.bounds.contains(try bounds("Table 5:", on: page)))
        #expect(region.bounds.contains(try bounds("0.69", on: page)))
        #expect(!region.bounds.intersects(try bounds("Unrelated prose", on: page)))
    }

    @Test(arguments: ["见表2中的结果。", "第2章介绍方法。"])
    func aChineseReferenceDoesNotRequireWhitespaceAfterItsNumber(source: String) throws {
        let isTable = source.contains("表")
        let fixture = try fixture(source: source, linked: "2", pages: [[
            (isTable ? "Table 2: Results." : "2. Method", 72, 700, false),
            ("Model", 72, 676, false), ("Train", 170, 676, false), ("Test", 260, 676, false),
            ("Alpha", 72, 660, false), ("0.91", 170, 660, false), ("0.88", 260, 660, false),
            ("Beta", 72, 644, false), ("0.72", 170, 644, false), ("0.69", 260, 644, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == (isTable ? "Table 2" : "Section 2"))
    }

    @Test
    func aLowercaseAppendixKeepsItsIdentifier() throws {
        let fixture = try fixture(source: "See Appendix a.", linked: "a", pages: [[
            ("a. Method", 72, 700, true),
            ("The opening paragraph provides the context.", 72, 676, false),
            ("Its continuation stays together.", 72, 660, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Section a")
    }

    @Test
    func aLowercaseAppendixTableKeepsItsWholeIdentifier() throws {
        let fixture = try fixture(source: "See Table a.1.", linked: "a.1", pages: [[
            ("Table a.1: Results.", 72, 700, false),
            ("Model", 72, 676, false), ("Train", 170, 676, false), ("Test", 260, 676, false),
            ("Alpha", 72, 660, false), ("0.91", 170, 660, false), ("0.88", 260, 660, false),
            ("Beta", 72, 644, false), ("0.72", 170, 644, false), ("0.69", 260, 644, false)
        ]], point: CGPoint(x: 72, y: 715))
        let region = try resolved(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Table a.1")
    }

    @Test
    func anUppercaseEquationSuffixDoesNotSelectTheUnsuffixedEquation() throws {
        let fixture = try fixture(source: "See Equation 1A.", linked: "1A", pages: [[
            ("x = y + z", 72, 700, false), ("(1)", 260, 700, false)
        ]], point: CGPoint(x: 72, y: 715))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A suffixed equation must not select a different, unsuffixed equation")
            return
        }
    }

    @Test(arguments: ["Table 2 — Additional details", "Section 2 — New approach"])
    func aWordAfterADashIsNotARangeEndpoint(reference: String) throws {
        let isTable = reference.hasPrefix("Table")
        let fixture = try fixture(source: "See \(reference).", linked: isTable ? "Additional" : "New", pages: [[
            (isTable ? "Table A: Results." : "N. Method", 72, 700, false),
            ("The opening paragraph provides the context.", 72, 676, false),
            ("Its continuation stays together.", 72, 660, false)
        ]], point: CGPoint(x: 72, y: 715))

        if case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) {
            #expect(region.title == nil)
        }
    }

    @Test
    func aNumberInAnotherSentenceDoesNotInheritAnEarlierTableKind() throws {
        let fixture = try fixture(source: "See Tables 2-5. There are 37 examples.", linked: "37", pages: [[
            ("A nearby paragraph is not the referenced table.", 72, 700, false),
            ("Its continuation must not be mistaken for a target.", 72, 684, false)
        ]], point: CGPoint(x: 72, y: 715))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A separate sentence must not inherit the preceding range's target kind")
            return
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func fixture(source: String, linked: String, pages: [[(String, Double, Double, Bool)]], point: CGPoint) throws -> Fixture {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for rows in [[(source, 40.0, 740.0, false)]] + pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (text, x, y, bold) in rows {
                (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                    .font: try #require(NSFont(name: bold ? "Helvetica-Bold" : "Helvetica", size: 12))
                ])
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let sourcePage = try #require(document.page(at: 0))
        let targetPage = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try bounds(linked, on: sourcePage), forType: .link, withProperties: nil)
        sourcePage.addAnnotation(annotation)
        let destination = PDFDestination(page: targetPage, at: point)
        annotation.destination = destination
        return Fixture(document: document, annotation: annotation, destination: destination)
    }

    private func resolved(_ fixture: Fixture) throws -> PDFReferencePreview.Region {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A structured target should resolve to its complete local object")
            throw MissingRegion()
        }
        return region
    }

    private func bounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let source = try #require(page.string) as NSString
        let range = source.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private struct MissingRegion: Error {}
}

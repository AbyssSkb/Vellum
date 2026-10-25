@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reference preview resolver")
struct PDFReferencePreviewResolverTests {
    @Test(arguments: [true, false])
    func textTablesIncludeTheirCaptionAndCellsWithoutTheAdjacentColumn(captionAbove: Bool) throws {
        let captionY: CGFloat = captionAbove ? 630 : 516
        var lines: [(String, NSPoint)] = [
            ("Table 2: Results.", NSPoint(x: 72, y: captionY)),
            ("Model", NSPoint(x: 72, y: 600)),
            ("Train", NSPoint(x: 190, y: 600)),
            ("Test", NSPoint(x: 300, y: 600)),
            ("Alpha", NSPoint(x: 72, y: 576)),
            ("0.91", NSPoint(x: 190, y: 576)),
            ("0.88", NSPoint(x: 300, y: 576)),
            ("Beta", NSPoint(x: 72, y: 552)),
            ("0.72", NSPoint(x: 190, y: 552)),
            ("0.69", NSPoint(x: 300, y: 552)),
            ("Other column.", NSPoint(x: 420, y: 600)),
            ("Unrelated prose.", NSPoint(x: 420, y: 576)),
            ("Following paragraph.", NSPoint(x: 72, y: 440))
        ]
        if captionAbove {
            lines.append(("Note: Held-out scores.", NSPoint(x: 72, y: 516)))
            lines.append(("Values use the same split.", NSPoint(x: 72, y: 492)))
        } else {
            lines.append(("Validation scores.", NSPoint(x: 72, y: 492)))
        }
        let fixture = try makeFixture(source: "See Table 2 for results.", linked: "2", lines: lines,
                                      point: CGPoint(x: 72, y: captionY + 12))

        let region = try resolvedRegion(fixture)

        for text in ["Table 2: Results.", "Model", "Train", "Test", "Alpha", "0.91", "0.88", "Beta", "0.72", "0.69"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        if captionAbove {
            #expect(region.bounds.contains(try textBounds("Note: Held-out scores.", on: fixture.page)))
            #expect(region.bounds.contains(try textBounds("Values use the same split.", on: fixture.page)))
        } else {
            #expect(region.bounds.contains(try textBounds("Validation scores.", on: fixture.page)))
        }
        for text in ["Other column.", "Unrelated prose.", "Following paragraph."] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
        #expect(region.title.map { AppUILanguage.english.text($0) } == "Table 2")
    }

    @Test
    func centeredTableCaptionIncludesRankedRowsWithoutAdjacentEquationNumbers() throws {
        let fixture = try makeFixture(source: "See Table 4 for scores.", linked: "4", lines: [
            ("Table 4: Scores.", NSPoint(x: 180, y: 630)),
            ("Model", NSPoint(x: 72, y: 600)),
            ("Train", NSPoint(x: 190, y: 600)),
            ("Test", NSPoint(x: 300, y: 600)),
            ("1 Alpha", NSPoint(x: 72, y: 576)),
            ("0.91", NSPoint(x: 190, y: 576)),
            ("0.88", NSPoint(x: 300, y: 576)),
            ("2 Beta", NSPoint(x: 72, y: 552)),
            ("0.72", NSPoint(x: 190, y: 552)),
            ("0.69", NSPoint(x: 300, y: 552)),
            ("Right column prose.", NSPoint(x: 420, y: 600)),
            ("(3)", NSPoint(x: 500, y: 576)),
            ("Following paragraph.", NSPoint(x: 72, y: 480))
        ], point: CGPoint(x: 180, y: 642))

        let region = try resolvedRegion(fixture)

        for text in ["Table 4: Scores.", "Model", "Train", "Test", "1 Alpha", "0.91", "0.88", "2 Beta", "0.72", "0.69"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["Right column prose.", "(3)", "Following paragraph."] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test
    func equationNumberSelectsTheExactSuffixEvenWhenTheDestinationIsNearAnotherEquation() throws {
        let fixture = try makeFixture(source: "Equation (3b) gives the result.", linked: "3b", lines: [
            ("x = y + 1", NSPoint(x: 120, y: 600)),
            ("(3a)", NSPoint(x: 500, y: 600)),
            ("z = x + y", NSPoint(x: 120, y: 520)),
            ("(3b)", NSPoint(x: 500, y: 520)),
            ("Following explanation.", NSPoint(x: 72, y: 450))
        ], point: CGPoint(x: 500, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds("z = x + y", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("(3b)", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("x = y + 1", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("(3a)", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("Following explanation.", on: fixture.page)))
        #expect(region.title.map { AppUILanguage.english.text($0) } == "Equation 3b")
    }

    @Test
    func equationIncludesSeparatedNumeratorDenominatorAndNumber() throws {
        let fixture = try makeFixture(source: "See Equation (8).", linked: "8", lines: [
            ("a + b", NSPoint(x: 190, y: 600)),
            ("--------", NSPoint(x: 185, y: 588)),
            ("c + d", NSPoint(x: 190, y: 576)),
            ("(8)", NSPoint(x: 500, y: 588)),
            ("Unrelated explanation.", NSPoint(x: 72, y: 510))
        ], point: CGPoint(x: 500, y: 600))

        let region = try resolvedRegion(fixture)

        for text in ["a + b", "--------", "c + d", "(8)"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        #expect(!region.bounds.intersects(try textBounds("Unrelated explanation.", on: fixture.page)))
    }

    @Test
    func sideBySideEquationsKeepOnlyTheMatchingFormula() throws {
        let fixture = try makeFixture(source: "See Equation (2a).", linked: "2a", lines: [
            ("x = y (1a)", NSPoint(x: 72, y: 600)),
            ("z = 3 (2a)", NSPoint(x: 300, y: 600))
        ], point: CGPoint(x: 300, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds("z = 3 (2a)", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("x = y (1a)", on: fixture.page)))
    }

    @Test
    func aBareParenthesizedEquationKeepsItsNumberWithoutACitationIdentity() throws {
        let fixture = try makeFixture(source: "See (2024) for the result.", linked: "2024", lines: [
            ("x = y + z", NSPoint(x: 120, y: 600)),
            ("(2024)", NSPoint(x: 500, y: 600)),
            ("An unrelated explanation.", NSPoint(x: 72, y: 540))
        ], point: CGPoint(x: 500, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Equation 2024")
        #expect(region.bounds.contains(try textBounds("x = y + z", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("(2024)", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("An unrelated explanation.", on: fixture.page)))
    }

    @Test(arguments: [
        ("The evaluation continued through April 1st,", "2024 to evaluate the complete model suite."),
        ("We retained the same evaluation split,", "128 samples per batch and identical metrics."),
        ("The evaluation covered the interval 2018-", "2024 with the same benchmark suite.")
    ])
    func numericSentenceContinuationsStayInsideTheSectionParagraph(lines: (String, String)) throws {
        let fixture = try makeFixture(source: "See Section 2.", linked: "2", lines: [
            ("2 Method", NSPoint(x: 72, y: 650)),
            (lines.0, NSPoint(x: 72, y: 618)),
            (lines.1, NSPoint(x: 72, y: 594)),
            ("The final sentence remains in the preview.", NSPoint(x: 72, y: 570)),
            ("3 Results", NSPoint(x: 72, y: 546)),
            ("An unrelated result paragraph.", NSPoint(x: 72, y: 522))
        ], point: CGPoint(x: 72, y: 662))

        let region = try resolvedRegion(fixture)

        for text in ["2 Method", lines.0, lines.1, "The final sentence remains in the preview."] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        #expect(!region.bounds.intersects(try textBounds("3 Results", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("An unrelated result paragraph.", on: fixture.page)))
    }

    @Test(arguments: [false, true])
    func numericHeadingsWithSeparateSpacingOrLargerTypeRemainBoundaries(largerType: Bool) throws {
        let fixture = try makeNamedFixture(name: "section.2", action: true, content: """
        BT /F1 12 Tf 72 680 Td (2. Method) Tj
        0 -26 Td (The introduction trails off,) Tj
        /F1 \(largerType ? 14 : 12) Tf 0 -\(largerType ? 16 : 28) Td (2024 Outlook) Tj
        /F1 12 Tf 0 -24 Td (An unrelated next paragraph.) Tj ET
        """)

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds("The introduction trails off,", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("2024 Outlook", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("An unrelated next paragraph.", on: fixture.page)))
    }

    @Test
    func paragraphDestinationsAfterANumericContinuationKeepTheOpeningLines() throws {
        let fixture = try makeFixture(source: "See this discussion.", linked: "discussion", lines: [
            ("2 Method", NSPoint(x: 72, y: 650)),
            ("The evaluation continued through April 1st,", NSPoint(x: 72, y: 618)),
            ("2024 to evaluate the complete model suite.", NSPoint(x: 72, y: 594)),
            ("The final sentence remains in the preview.", NSPoint(x: 72, y: 570)),
            ("3 Results", NSPoint(x: 72, y: 546))
        ], point: CGPoint(x: 100, y: 580))

        let region = try resolvedRegion(fixture)

        for text in ["The evaluation continued", "2024 to evaluate", "The final sentence"] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        #expect(!region.bounds.intersects(try textBounds("2 Method", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("3 Results", on: fixture.page)))
    }

    @Test
    func sectionIncludesTheHeadingAndFirstParagraphThenStops() throws {
        let fixture = try makeFixture(source: "Section 2 describes the method.", linked: "2", lines: [
            ("2 Method", NSPoint(x: 72, y: 650)),
            ("The method has two stages.", NSPoint(x: 72, y: 618)),
            ("Both preserve the context.", NSPoint(x: 72, y: 594)),
            ("A separate paragraph.", NSPoint(x: 72, y: 540)),
            ("3 Results", NSPoint(x: 72, y: 484)),
            ("Other column.", NSPoint(x: 420, y: 618))
        ], point: CGPoint(x: 72, y: 662))

        let region = try resolvedRegion(fixture)

        for text in ["2 Method", "The method has two stages.", "Both preserve the context."] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["A separate paragraph.", "3 Results", "Other column."] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
        #expect(region.title.map { AppUILanguage.english.text($0) } == "Section 2")
    }

    @Test(arguments: ["section.2", "subsection.2.1", "subsubsection.2.1.1", "appendix.B", "subsection.B.1"], [false, true])
    func namedSectionTargetsKeepTheirHeadingInsteadOfThePrecedingParagraph(name: String, action: Bool) throws {
        let fixture = try makeNamedFixture(name: name, action: action)
        let number = name.split(separator: ".").dropFirst().joined(separator: ".")

        let region = try resolvedRegion(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Section \(number)")
        for text in ["\(number). Method", "The first paragraph starts here.", "Its continuation remains together."] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["The preceding paragraph ends here.", "A separate following paragraph."] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test
    func aNamedSectionWhoseHeadingIsOnAnotherPageKeepsPageContext() throws {
        let fixture = try makeNamedFixture(name: "subsection.2.2", action: true, hasHeading: false)

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A section anchor before a page break must not crop the preceding paragraph")
            return
        }
    }

    @Test
    func aSectionAnchorBeforeAPageBreakUsesTheHeadingOnTheNextPage() throws {
        let fixture = try makeNamedFixture(name: "subsection.2.2", action: true, hasHeading: false)
        let nextDocument = try makeTextPDF(pages: [[
            ("2.2. Decoder", NSPoint(x: 72, y: 700)),
            ("The first paragraph starts here.", NSPoint(x: 72, y: 676)),
            ("Its continuation remains together.", NSPoint(x: 72, y: 652)),
            ("A separate following paragraph.", NSPoint(x: 84, y: 604))
        ]])
        let nextPage = try #require(nextDocument.page(at: 0))
        fixture.document.insert(nextPage, at: 2)

        let region = try resolvedRegion(fixture)

        #expect(region.destination?.page === nextPage)
        #expect(region.bounds.contains(try textBounds("2.2. Decoder", on: nextPage)))
        #expect(region.bounds.contains(try textBounds("Its continuation remains together.", on: nextPage)))
        #expect(!region.bounds.intersects(try textBounds("A separate following paragraph.", on: nextPage)))
    }

    @Test
    func aParentSectionIncludesItsDescendantHeadingsAndTheirFirstParagraph() throws {
        let fixture = try makeFixture(source: "See Section 2.", linked: "2", lines: [
            ("2. Method", NSPoint(x: 72, y: 700)),
            ("2.1. Design", NSPoint(x: 72, y: 676)),
            ("2.1.1. Details", NSPoint(x: 72, y: 652)),
            ("The first paragraph starts here.", NSPoint(x: 72, y: 628)),
            ("Its continuation remains together.", NSPoint(x: 72, y: 604)),
            ("2.1.2. Separate sibling", NSPoint(x: 72, y: 580))
        ], point: CGPoint(x: 72, y: 712))

        let region = try resolvedRegion(fixture)

        for text in ["2. Method", "2.1. Design", "2.1.1. Details", "The first paragraph starts here.", "Its continuation remains together."] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        #expect(!region.bounds.intersects(try textBounds("2.1.2. Separate sibling", on: fixture.page)))
    }

    @Test(arguments: ["Figure 12 shows the result.", "Table 3 compares the models.", "A method starts with shared context."])
    func aParagraphStartingWithAReferenceIsNotMistakenForACaption(text: String) throws {
        let fixture = try makeFixture(source: "See Section 2.", linked: "2", lines: [
            ("2. Method", NSPoint(x: 72, y: 700)),
            (text, NSPoint(x: 72, y: 676)),
            ("Its continuation remains together.", NSPoint(x: 72, y: 652)),
            ("A separate following paragraph.", NSPoint(x: 84, y: 604))
        ], point: CGPoint(x: 72, y: 712))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("Its continuation remains together.", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("A separate following paragraph.", on: fixture.page)))
    }

    @Test(arguments: [false, true])
    func aSectionParagraphContinuesAcrossAPageBreakWithoutTheNextParagraph(hasFloatingCaption: Bool) throws {
        let fixture = try makeFixture(source: "See Section 2.", linked: "2", lines: [
            ("2. Method", NSPoint(x: 72, y: 130)),
            ("The first paragraph describes the", NSPoint(x: 72, y: 106)),
            ("Transformer layers with a shared cache", NSPoint(x: 72, y: 82)),
            ("2", NSPoint(x: 300, y: 40))
        ], point: CGPoint(x: 72, y: 142))
        var lines: [(String, NSPoint)] = [
            ("Transformer blocks and their complete result.", NSPoint(x: 72, y: hasFloatingCaption ? 580 : 700)),
            ("Both stages remain together.", NSPoint(x: 72, y: hasFloatingCaption ? 556 : 676)),
            ("A separate following paragraph.", NSPoint(x: 84, y: hasFloatingCaption ? 508 : 628))
        ]
        if hasFloatingCaption {
            lines += [("Figure 8: An unrelated floating graphic.", NSPoint(x: 72, y: 700)),
                      ("The caption continues here.", NSPoint(x: 72, y: 676))]
        }
        let nextDocument = try makeTextPDF(pages: [lines])
        let nextPage = try #require(nextDocument.page(at: 0))
        fixture.document.insert(nextPage, at: 2)

        let region = try resolvedRegion(fixture)
        let continuation = try #require(region.continuation)

        #expect(continuation.page === nextPage)
        #expect(continuation.bounds.contains(try textBounds("Transformer blocks and their complete result.", on: nextPage)))
        #expect(continuation.bounds.contains(try textBounds("Both stages remain together.", on: nextPage)))
        #expect(!continuation.bounds.intersects(try textBounds("A separate following paragraph.", on: nextPage)))
        if hasFloatingCaption {
            #expect(!continuation.bounds.intersects(try textBounds("Figure 8:", on: nextPage)))
        }
    }

    @Test(arguments: ["formula", "quote", "list"])
    func aSectionIncludesTheBlockIntroducedByAColon(kind: String) throws {
        let block: [(String, NSPoint)]
        switch kind {
        case "formula": block = [("x = y + z", NSPoint(x: 120, y: 616)), ("z = 2", NSPoint(x: 180, y: 592))]
        case "quote": block = [("Reasoning effort: high", NSPoint(x: 90, y: 616)), ("Use the complete context.", NSPoint(x: 90, y: 592))]
        default: block = [("• First category", NSPoint(x: 90, y: 616)), ("• Second category", NSPoint(x: 90, y: 592))]
        }
        let fixture = try makeFixture(source: "See Section 2.", linked: "2", lines: [
            ("2. Method", NSPoint(x: 72, y: 700)),
            ("The method is defined as follows:", NSPoint(x: 72, y: 676))
        ] + block + [
            ("where both stages preserve context.", NSPoint(x: 72, y: 556)),
            ("A separate following paragraph.", NSPoint(x: 84, y: 508))
        ], point: CGPoint(x: 72, y: 712))

        let region = try resolvedRegion(fixture)

        for (text, _) in block {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        #expect(region.bounds.contains(try textBounds("where both stages preserve context.", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("A separate following paragraph.", on: fixture.page)))
    }

    @Test
    func aDistantFullWidthCaptionDoesNotExpandASectionIntoTheAdjacentColumn() throws {
        let fixture = try makeFixture(source: "See Section 2.", linked: "2", lines: [
            ("2. Method", NSPoint(x: 72, y: 700)),
            ("The left paragraph starts.", NSPoint(x: 72, y: 676)),
            ("Its continuation stays here.", NSPoint(x: 72, y: 652)),
            ("Right column.", NSPoint(x: 420, y: 676)),
            ("Right continuation.", NSPoint(x: 420, y: 652)),
            ("Figure 8: A full-width caption spans both reading columns.", NSPoint(x: 72, y: 100)),
            ("The caption continues across the full width of the page.", NSPoint(x: 72, y: 76))
        ], point: CGPoint(x: 72, y: 722))

        let region = try resolvedRegion(fixture)

        for text in ["2. Method", "The left paragraph starts.", "Its continuation stays here."] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        for text in ["Right column.", "Right continuation.", "Figure 8:", "The caption continues"] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test(arguments: ["Sec-", "tion 6"])
    func aSectionReferenceSplitAcrossLinesKeepsItsTargetType(linked: String) throws {
        let fixture = try makeFixture(source: "See Sec-\ntion 6 for details.", linked: linked, lines: [
            ("6 Results", NSPoint(x: 72, y: 600)),
            ("The results preserve the full context.", NSPoint(x: 72, y: 576)),
            ("Both stages remain deterministic.", NSPoint(x: 72, y: 552)),
            ("An unrelated paragraph.", NSPoint(x: 72, y: 480))
        ], point: CGPoint(x: 72, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.title.map { AppUILanguage.english.text($0) } == "Section 6")
        #expect(region.bounds.contains(try textBounds("6 Results", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("Both stages", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("An unrelated", on: fixture.page)))
    }

    @Test(arguments: [false, true])
    func namedAlgorithmsKeepTheirWholeFrameAndInputConditions(action: Bool) throws {
        let fixture = try makeNamedFixture(name: "algorithm.1", action: action, content: """
            BT /F1 12 Tf 72 650 Td (Algorithm 1 Balanced update) Tj ET
            BT /F1 10 Tf 72 632 Td (Require: Matrix, gradient and learning rate.) Tj 0 -14 Td (An odd number of normalization steps.) Tj ET
            BT /F1 10 Tf 72 594 Td (1: Normalize the matrix.) Tj 0 -16 Td (2: Update the weights.) Tj 0 -16 Td (3: Return the result.) Tj ET
            BT /F1 10 Tf 350 578 Td (Retain this side comment.) Tj ET
            0.5 w 72 666 m 540 666 l S 72 646 m 540 646 l S 72 550 m 540 550 l S
            BT /F1 12 Tf 72 510 Td (An unrelated paragraph follows.) Tj ET
            """)

        let region = try resolvedRegion(fixture)

        for text in ["Algorithm 1", "Require:", "An odd number", "1: Normalize", "2: Update", "3: Return", "Retain this side comment."] {
            #expect(region.bounds.contains(try textBounds(text, on: fixture.page)))
        }
        #expect(region.bounds.contains(CGRect(x: 72, y: 549.75, width: 468, height: 116.5)))
        #expect(!region.bounds.intersects(try textBounds("An unrelated paragraph", on: fixture.page)))
        #expect(region.title.map { AppUILanguage.english.text($0) } == "Algorithm 1")
        #expect(region.title.map { AppUILanguage.chinese.text($0) } == "算法 1")
    }

    @Test(arguments: ["Algorithm 1", "Theorem 1", "footnote 1", "Algorithms 1 and 2"], [false, true])
    func unclassifiedNumericLinksKeepPageContextInsteadOfCroppingNearbyProse(reference: String, wholePhrase: Bool) throws {
        let fixture = try makeFixture(source: "See \(reference).", linked: wholePhrase ? reference : "1", lines: [
            ("A preceding ordinary paragraph.", NSPoint(x: 72, y: 600)),
            ("Its continuation does not contain the target.", NSPoint(x: 72, y: 576))
        ], point: CGPoint(x: 72, y: 612))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("An unclassified numbered object must not preview an arbitrary paragraph")
            return
        }
    }

    @Test
    func genericTextReferenceKeepsItsWholeParagraphAndColumn() throws {
        let fixture = try makeFixture(source: "See the discussion for details.", linked: "discussion", lines: [
            ("A compact first line.", NSPoint(x: 72, y: 600)),
            ("Its continuation stays here.", NSPoint(x: 72, y: 576)),
            ("Another paragraph.", NSPoint(x: 72, y: 510)),
            ("Right column text.", NSPoint(x: 420, y: 600)),
            ("Right continuation.", NSPoint(x: 420, y: 576))
        ], point: CGPoint(x: 100, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds("A compact first line.", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("Its continuation stays here.", on: fixture.page)))
        for text in ["Another paragraph.", "Right column text.", "Right continuation."] {
            #expect(!region.bounds.intersects(try textBounds(text, on: fixture.page)))
        }
    }

    @Test
    func anIndentedParagraphDoesNotIncludeThePreviousParagraphAtUniformSpacing() throws {
        let fixture = try makeFixture(source: "See the discussion for details.", linked: "discussion", lines: [
            ("The previous paragraph ends.", NSPoint(x: 72, y: 624)),
            ("An indented paragraph starts.", NSPoint(x: 84, y: 600)),
            ("Its second line continues.", NSPoint(x: 72, y: 576)),
            ("Following paragraph.", NSPoint(x: 72, y: 510))
        ], point: CGPoint(x: 100, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds("An indented paragraph starts.", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("Its second line continues.", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("The previous paragraph ends.", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("Following paragraph.", on: fixture.page)))
    }

    @Test
    func appendixEquationMatchesItsDottedNumberAndIndependentLabel() throws {
        let fixture = try makeFixture(source: "Equation (A.1) gives the result.", linked: "A.1", lines: [
            ("The appendix introduces the result.", NSPoint(x: 72, y: 650)),
            ("x = y + z", NSPoint(x: 120, y: 600)),
            ("(A.1)", NSPoint(x: 500, y: 600)),
            ("An unrelated explanation.", NSPoint(x: 72, y: 540))
        ], point: CGPoint(x: 500, y: 612))

        let region = try resolvedRegion(fixture)

        #expect(region.bounds.contains(try textBounds("x = y + z", on: fixture.page)))
        #expect(region.bounds.contains(try textBounds("(A.1)", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("The appendix introduces the result.", on: fixture.page)))
        #expect(!region.bounds.intersects(try textBounds("An unrelated explanation.", on: fixture.page)))
        #expect(region.title.map { AppUILanguage.english.text($0) } == "Equation A.1")
    }

    @Test(arguments: [false, true])
    func targetsWithoutLocalTextKeepThePageContext(hasDistantText: Bool) throws {
        let lines = hasDistantText ? [("Distant footer.", NSPoint(x: 72, y: 50))] : []
        let fixture = try makeFixture(source: "See the discussion.", linked: "discussion", lines: lines,
                                      point: CGPoint(x: 300, y: 650))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A target without local text should retain its page context")
            return
        }
    }

    @Test
    func aFigureTargetWithoutATextLayerKeepsItsPageContext() throws {
        let fixture = try makeFixture(source: "See Figure 1.", linked: "1", lines: [], point: CGPoint(x: 300, y: 650))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("A page without a text layer should remain previewable")
            return
        }
    }

    @Test(arguments: ["Figure 9", "Table 9", "Algorithm 9", "Equation (9)", "Section 9"])
    func unresolvedExplicitTargetsDoNotCropUnrelatedText(reference: String) throws {
        let fixture = try makeFixture(source: "See \(reference) for details.", linked: "9", lines: [
            ("Ordinary target text.", NSPoint(x: 72, y: 600)),
            ("It is not the named target.", NSPoint(x: 72, y: 576))
        ], point: CGPoint(x: 100, y: 612))

        guard case .pageContext = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("An uncertain boundary should retain target page context instead of blocking preview or cropping unrelated text")
            return
        }
    }

    private struct Fixture {
        let document: PDFDocument
        let page: PDFPage
        let annotation: PDFAnnotation
        let destination: PDFDestination
    }

    private func makeFixture(source: String, linked: String, lines: [(String, NSPoint)], point: CGPoint) throws -> Fixture {
        let document = try makeTextPDF(pages: [[(source, NSPoint(x: 40, y: 650))], lines])
        let sourcePage = try #require(document.page(at: 0))
        let page = try #require(document.page(at: 1))
        let annotation = PDFAnnotation(bounds: try textBounds(linked, on: sourcePage), forType: .link, withProperties: nil)
        sourcePage.addAnnotation(annotation)
        let destination = PDFDestination(page: page, at: point)
        annotation.destination = destination
        return Fixture(document: document, page: page, annotation: annotation, destination: destination)
    }

    private func makeNamedFixture(name: String, action: Bool, hasHeading: Bool = true, content: String? = nil) throws -> Fixture {
        let number = name.split(separator: ".").dropFirst().joined(separator: ".")
        let source = "BT /F1 12 Tf 40 700 Td (Method, and design) Tj ET"
        let target = content ?? ("BT /F1 12 Tf 72 655 Td (The preceding paragraph begins here.) Tj 0 -16 Td (The preceding paragraph ends here.) Tj ET\n"
            + (hasHeading ? "BT /F1 12 Tf 72 600 Td (\(number). Method) Tj 0 -24 Td (The first paragraph starts here.) Tj 0 -14 Td (Its continuation remains together.) Tj 0 -42 Td (A separate following paragraph.) Tj ET" : ""))
        let destination = action ? "(\(name))" : "/\(name)"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /Dests << /\(name) [5 0 R /XYZ 48 627 null] >> /Names << /Dests << /Names [(\(name)) [5 0 R /XYZ 48 627 null]] >> >> >>",
            "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R /Annots [8 0 R] >>",
            "<< /Length \(source.utf8.count) >>\nstream\n\(source)\nendstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
            "<< /Length \(target.utf8.count) >>\nstream\n\(target)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Annot /Subtype /Link /Rect [40 697 145 714] \(action ? "/A << /S /GoTo /D \(destination) >>" : "/Dest \(destination)") >>"
        ]
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
        return Fixture(document: document, page: page, annotation: annotation,
                       destination: PDFDestination(page: page, at: CGPoint(x: 48, y: 627)))
    }

    private func resolvedRegion(_ fixture: Fixture) throws -> PDFReferencePreview.Region {
        guard case .region(let region) = PDFReferencePreview.resolve(for: fixture.annotation, destination: fixture.destination) else {
            Issue.record("The reference should resolve to a local content region")
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

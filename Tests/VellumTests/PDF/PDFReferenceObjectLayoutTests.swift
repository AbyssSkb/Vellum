import Foundation
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reference object ownership")
struct PDFReferenceObjectLayoutTests {
    private let crop = CGRect(x: 0, y: 0, width: 612, height: 792)

    @Test
    func narrowBodyOwnsItsRulesIndependentlyOfWideCaption() throws {
        let lines = [
            line("Table 2 | Mapping public tiers to scalar effort.", 72, 700, 460, 11),
            line("The caption continues here.", 72, 686, 160, 11),
            line("Tier", 240, 662, 35, 10), line("Value", 304, 662, 45, 10),
            line("max", 240, 642, 20, 10), line("100", 312, 642, 20, 10),
            line("low", 240, 628, 20, 10), line("50", 315, 628, 15, 10)
        ]
        let rules = [rule(234, 680, 127), rule(234, 657, 127), rule(234, 620, 127)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .table, number: "2", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.flatMap(\.ruleIndices)) == Set(rules.indices))
        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(lines.indices))
        #expect(object.bounds.contains(rules[2]))
    }

    @Test
    func subpointEndpointDifferenceDoesNotDiscardClosingBorder() throws {
        let lines = tableLines()
        let rules = [rule(70.866, 680, 463.208), rule(70.8, 656, 463.3), rule(70.9, 620, 463.2)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.flatMap(\.ruleIndices)) == Set(rules.indices))
        #expect(object.bounds.contains(rules[2]))
    }

    @Test(arguments: ["Note. Scores share the same evaluation conditions.",
                      "Note: Scores share the same evaluation conditions.",
                      "Scores share the same evaluation conditions."])
    func smallAttachedNotesBelongToTableRegardlessOfPrefix(text: String) throws {
        let lines = tableLines() + [
            line(text, 72, 608, 390, 8),
            line("Values are averaged over repeated runs.", 72, 598, 360, 8),
            line("An ordinary body paragraph follows the completed object.", 72, 576, 455, 12)
        ]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: tableRules(), crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.filter { $0.role == .note }.flatMap(\.lineIndices)) == [7, 8])
        #expect(!object.parts.flatMap(\.lineIndices).contains(9))
        #expect(!object.bounds.intersects(lines[9].bounds))
    }

    @Test
    func noteParagraphStopsAtALargerBreakEvenWithIdenticalFonts() throws {
        let note = PDFReferenceTextLayout.Line(bounds: CGRect(x: 72, y: 602, width: 300, height: 14),
                                               text: "Note: Scores use the same split.", fontSize: 12)
        let continuation = PDFReferenceTextLayout.Line(bounds: CGRect(x: 72, y: 588, width: 350, height: 14),
                                                       text: "The uncertainty is across random seeds.", fontSize: 12)
        let unrelated = PDFReferenceTextLayout.Line(bounds: CGRect(x: 72, y: 560, width: 450, height: 14),
                                                    text: "A separate paragraph follows the table.", fontSize: 12)
        let lines = tableLines() + [note, continuation, unrelated]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: tableRules(), crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.filter { $0.role == .note }.flatMap(\.lineIndices)) == [7, 8])
        #expect(!object.parts.flatMap(\.lineIndices).contains(9))
    }

    @Test
    func captionBelowBodyIncludesItsContinuation() throws {
        var lines = tableLines()
        lines[0] = line("Table 1: Results under a fixed budget.", 72, 600, 350, 12)
        lines.append(line("The uncertainty is measured across random seeds.", 72, 586, 450, 12))
        lines.append(line("Unrelated discussion starts below.", 72, 554, 300, 12))
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: tableRules(), crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 612)))

        #expect(Set(object.parts.filter { $0.role == .caption }.flatMap(\.lineIndices)) == [0, 7])
        #expect(!object.parts.flatMap(\.lineIndices).contains(8))
    }

    @Test
    func neighboringTableWithSameRuleWidthRemainsSeparate() throws {
        let second = [
            line("Table 2: Other results.", 72, 570, 260, 12),
            line("Gamma", 72, 534, 70, 10), line("0.5", 330, 534, 30, 10),
            line("Delta", 72, 512, 70, 10), line("0.4", 330, 512, 30, 10)
        ]
        let lines = tableLines() + second
        let rules = tableRules() + [rule(72, 550, 460), rule(72, 528, 460), rule(72, 500, 460)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.flatMap(\.ruleIndices)) == [0, 1, 2])
        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(0..<7))
        #expect(!object.bounds.intersects(second[0].bounds))
    }

    @Test
    func framedAlgorithmOwnsTitleInputsCodeCommentsAndClosingRule() throws {
        let lines = [
            line("Algorithm 1 Momentum update", 72, 688, 300, 10),
            line("Require: Weights, gradients and a positive step count.", 72, 666, 460, 10),
            line("1: Initialize the accumulated gradient", 78, 646, 240, 10),
            line("2: W ← W − G", 78, 626, 140, 10),
            line("⊲ Update the weights", 390, 626, 140, 10),
            line("A separate paragraph discusses the algorithm afterwards.", 72, 570, 455, 12)
        ]
        let rules = [rule(72, 704, 460), rule(72, 684, 460), rule(72, 610, 460)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .algorithm, number: "1", near: CGPoint(x: 72, y: 700)))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(0..<5))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == Set(rules.indices))
        #expect(!object.bounds.intersects(lines[5].bounds))
    }

    @Test
    func centeredCaptionUsesTheOwnerWidthForContinuationAndKeepsShortCrossReferences() {
        let lines = [
            line("Figure 2: Numerical results in", 180, 640, 210, 12),
            line("The full comparison is available in", 72, 626, 455, 12),
            line("Table 13.", 72, 612, 40, 6),
            line("The document body resumes after the caption.", 72, 580, 450, 12)
        ]
        let owner = CGRect(x: 72, y: 660, width: 460, height: 100)
        let parts = PDFReferenceObjectLayout(lines: lines, rules: [], crop: crop)
            .caption(startingAt: lines[0].bounds, owner: owner)

        #expect(Set(parts.flatMap(\.lineIndices)) == [0, 1, 2])
    }

    @Test
    func captionStopsAtANewDescribedObject() {
        let lines = [
            line("Figure 2: Results.", 72, 640, 210, 12),
            line("Figure 3: A separate comparison.", 72, 626, 280, 12)
        ]
        let owner = CGRect(x: 72, y: 660, width: 460, height: 100)
        let parts = PDFReferenceObjectLayout(lines: lines, rules: [], crop: crop)
            .caption(startingAt: lines[0].bounds, owner: owner)

        #expect(parts.flatMap(\.lineIndices) == [0])
    }

    @Test
    func unruledColumnHeaderCanBeWiderThanTheAlignedNumericValues() throws {
        let lines = tableLines() + [line("Unrelated column", 440, 664, 120, 10)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: [], crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.filter { $0.role == .body }.flatMap(\.lineIndices)) == Set(1..<7))
        #expect(object.bounds.contains(lines[2].bounds))
        #expect(!object.bounds.intersects(lines[7].bounds))
    }

    @Test
    func firstCaptionRowKeepsEveryFragmentAndTheProvidedBounds() {
        let lines = [
            line("Figure 2: Results under a", 72, 640, 210, 12),
            line("fixed budget.", 308, 640, 100, 12),
            line("The sample size is fixed.", 72, 626, 160, 12)
        ]
        let first = CGRect(x: 72, y: 640, width: 336.5, height: 12)
        let parts = PDFReferenceObjectLayout(lines: lines, rules: [], crop: crop)
            .caption(startingAt: first, owner: CGRect(x: 72, y: 660, width: 210, height: 100))

        #expect(Set(parts.flatMap(\.lineIndices)) == Set(lines.indices))
        #expect(PDFReferenceObjectLayout.Object(parts: parts).bounds.contains(first))
    }

    @Test
    func framedAlgorithmKeepsStepsWhoseNumbersHaveNoPunctuation() throws {
        let lines = [
            line("Algorithm 1 Momentum update", 72, 688, 300, 10),
            line("Require: Weights and gradients", 72, 666, 300, 10),
            line("1 Initialize the accumulated gradient", 78, 646, 240, 10),
            line("2 Update the weights", 78, 626, 140, 10)
        ]
        let rules = [rule(72, 704, 460), rule(72, 684, 460), rule(72, 610, 460)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .algorithm, number: "1", near: CGPoint(x: 72, y: 700)))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(lines.indices))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == Set(rules.indices))
    }

    @Test
    func algorithmStopsBeforeANewSectionAndProseDespiteAlignedRules() throws {
        let lines = [
            line("Algorithm 1 Momentum update", 72, 688, 300, 10),
            line("Require: Weights and gradients", 72, 666, 300, 10),
            line("1 Initialize the accumulated gradient", 78, 646, 240, 10),
            line("2 Update the weights", 78, 626, 140, 10),
            line("3 Discussion", 72, 580, 200, 16),
            line("A separate paragraph describes how the model is trained and evaluated.", 72, 558, 450, 12)
        ]
        let rules = [rule(72, 704, 460), rule(72, 684, 460), rule(72, 610, 460), rule(72, 540, 460)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .algorithm, number: "1", near: CGPoint(x: 72, y: 700)))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(0..<4))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == [0, 1, 2])
    }

    @Test
    func compactFramedHeaderCanContainALongNonnumericLine() throws {
        let lines = [
            line("Dimension", 72, 684, 65, 10), line("Batch", 170, 684, 45, 10),
            line("Without fusion", 270, 684, 100, 10), line("With fusion", 420, 684, 100, 10),
            line("Prefill Time (ms) Decode Time (ms) Prefill Time (ms) Decode Time (ms)", 220, 674, 300, 7),
            line("4096", 72, 648, 30, 9), line("1", 170, 648, 10, 9),
            line("0.2", 270, 648, 25, 9), line("0.1", 420, 648, 25, 9),
            line("4096", 72, 630, 30, 9), line("2", 170, 630, 10, 9),
            line("0.4", 270, 630, 25, 9), line("0.2", 420, 630, 25, 9),
            line("Table 6: Kernel timing results.", 72, 600, 350, 12)
        ]
        let rules = [rule(72, 700, 460), rule(220, 683, 312), rule(72, 668, 460), rule(72, 620, 460)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .table, number: "6", near: CGPoint(x: 72, y: 612)))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(lines.indices))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == Set(rules.indices))
        #expect(object.bounds.contains(rules[0]))
    }

    @Test
    func sparseRowsStayInsideFramedTable() throws {
        let lines = tableLines() + [
            line("Tools with constrained output", 72, 610, 220, 10),
            line("-", 330, 610, 5, 10), line("-", 420, 610, 5, 10),
            line("Final task", 72, 590, 75, 10), line("0.8", 330, 590, 30, 10)
        ]
        let rules = [rule(72, 680, 460), rule(72, 656, 460), rule(72, 620, 460), rule(72, 580, 460)]
        let object = try #require(PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .table, number: "1", near: CGPoint(x: 72, y: 710)))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(lines.indices))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == Set(rules.indices))
    }

    private func tableLines() -> [PDFReferenceTextLayout.Line] {
        [line("Table 1: Evaluation results.", 72, 700, 350, 12),
         line("Model", 72, 664, 80, 10), line("Score", 330, 664, 50, 10),
         line("Alpha", 72, 644, 70, 10), line("0.9", 330, 644, 30, 10),
         line("Beta", 72, 628, 70, 10), line("0.7", 330, 628, 30, 10)]
    }

    private func tableRules() -> [CGRect] { [rule(72, 680, 460), rule(72, 656, 460), rule(72, 620, 460)] }

    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ size: CGFloat) -> PDFReferenceTextLayout.Line {
        PDFReferenceTextLayout.Line(bounds: CGRect(x: x, y: y, width: width, height: size), text: text, fontSize: size)
    }

    private func rule(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: 0.5)
    }
}

import Foundation
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF framed text table ownership")
struct PDFPromptTablePreviewTests {
    private let crop = CGRect(x: 0, y: 0, width: 612, height: 792)

    @Test(arguments: [false, true])
    func insetTextCellOwnsProseBetweenItsRules(captionAbove: Bool) throws {
        let fixture = promptTable(captionAbove: captionAbove)
        let object = try #require(resolve(fixture.lines, rules: fixture.rules))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(0..<7))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == [0, 1])
        #expect(object.bounds.contains(fixture.rules[0]))
        #expect(object.bounds.contains(fixture.rules[1]))
        #expect(!object.bounds.intersects(fixture.lines[7].bounds))
        #expect(!object.bounds.intersects(fixture.lines[8].bounds))
    }

    @Test
    func alignedRulesDoNotTurnFlushBodyProseIntoATable() {
        var fixture = promptTable(captionAbove: false)
        for index in 1..<7 {
            let old = fixture.lines[index]
            fixture.lines[index] = line(old.text, 122, old.bounds.minY, old.bounds.width, 10)
        }

        #expect(resolve(fixture.lines, rules: fixture.rules) == nil)
    }

    @Test
    func insetProseNeedsAnAdjacentCaption() {
        var fixture = promptTable(captionAbove: false)
        fixture.lines[0] = line("Table 8: An example evaluation input.", 160, 500, 260, 11)

        #expect(resolve(fixture.lines, rules: fixture.rules) == nil)
    }

    @Test(arguments: ["3 Discussion", "Table 9: A different object."])
    func insetTextDoesNotCrossATypographicallyDistinctHeadingOrAnotherCaption(boundary: String) {
        var fixture = promptTable(captionAbove: false)
        fixture.lines[3] = line(boundary, 128, 636, 260, boundary.hasPrefix("3") ? 13 : 10)

        #expect(resolve(fixture.lines, rules: fixture.rules) == nil)
    }

    @Test
    func separateBodyProseAfterAnInsetTableIsNotOwnedDespiteAlignedSeparator() throws {
        var fixture = promptTable(captionAbove: true)
        fixture.lines.append(line("An unrelated paragraph discusses the method after the complete framed object.", 128, 556, 335, 12))
        fixture.lines.append(line("Its ordinary body text should remain outside the table preview content.", 128, 542, 335, 12))
        fixture.rules.append(rule(122, 526, 352))
        let object = try #require(resolve(fixture.lines, rules: fixture.rules))

        #expect(Set(object.parts.flatMap(\.lineIndices)) == Set(0..<7))
        #expect(Set(object.parts.flatMap(\.ruleIndices)) == [0, 1])
        #expect(!object.bounds.intersects(fixture.lines[9].bounds))
        #expect(!object.bounds.intersects(fixture.lines[10].bounds))
    }

    @Test
    func largerBodyProseBetweenSeparatorsRemainsExcluded() {
        var fixture = promptTable(captionAbove: false)
        for index in 1..<7 {
            let old = fixture.lines[index]
            fixture.lines[index] = line(old.text, 128, old.bounds.minY, old.bounds.width, 12)
        }

        #expect(resolve(fixture.lines, rules: fixture.rules) == nil)
    }

    private func promptTable(captionAbove: Bool) -> (lines: [PDFReferenceTextLayout.Line], rules: [CGRect]) {
        let lines = [
            line("Table 8: An example evaluation input.", 160, captionAbove ? 692 : 566, 260, 11),
            line("Example", 128, 662, 40, 10),
            line("Read the supplied function and complete its assertion with the resulting output.", 128, 650, 338, 10),
            line("Provide a literal value and do not include any unrelated explanation or commentary.", 128, 638, 338, 10),
            line("The following input demonstrates how the evaluation request should be formatted.", 128, 626, 330, 10),
            line("def evaluate(value):", 128, 614, 120, 10),
            line("    return value", 128, 602, 85, 10),
            line("A normal paragraph before the object should never become part of this table.", 72, 730, 455, 12),
            line("Another normal paragraph continues after the complete table and its caption.", 72, 522, 455, 12)
        ]
        return (lines, [rule(122, 680, 352), rule(122, 588, 352)])
    }

    private func resolve(_ lines: [PDFReferenceTextLayout.Line], rules: [CGRect]) -> PDFReferenceObjectLayout.Object? {
        PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
            .object(kind: .table, number: "8", near: lines[0].bounds.origin)
    }

    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ size: CGFloat) -> PDFReferenceTextLayout.Line {
        PDFReferenceTextLayout.Line(bounds: CGRect(x: x, y: y, width: width, height: size), text: text, fontSize: size)
    }

    private func rule(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: 0.5)
    }
}

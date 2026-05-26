@preconcurrency import AppKit
import Testing
@testable import Vellum

@Suite("Text selection range builder")
struct TextSelectionRangeBuilderTests {
    @Test
    func contiguousOffsetsBecomeHalfOpenRanges() {
        let ranges = TextSelectionRangeBuilder.contiguousRanges(from: [3, 4, 5, 9, 10, 14])

        #expect(ranges == [3..<6, 9..<11, 14..<15])
    }

    @Test
    func visualLineSlotsAreClampedAndConvertedToPageLocalRanges() {
        let line = VimTextLine(
            pageIndex: 0,
            startOffset: 100,
            endOffset: 110,
            midY: 0,
            characters: [
                character(offset: 102),
                character(offset: 103),
                character(offset: 107),
                character(offset: 108)
            ]
        )

        let ranges = TextSelectionRangeBuilder.pageRanges(
            for: line,
            startSlot: -4,
            endSlot: 99,
            pageStart: 100
        )

        #expect(ranges == [2..<4, 7..<9])
    }

    @Test
    func emptyOrReversedSlotsProduceNoRanges() {
        let line = VimTextLine(
            pageIndex: 0,
            startOffset: 0,
            endOffset: 2,
            midY: 0,
            characters: [character(offset: 0), character(offset: 1)]
        )

        #expect(TextSelectionRangeBuilder.pageRanges(for: line, startSlot: 1, endSlot: 1, pageStart: 0).isEmpty)
        #expect(TextSelectionRangeBuilder.pageRanges(for: line, startSlot: 2, endSlot: 0, pageStart: 0).isEmpty)
    }

    private func character(offset: Int) -> VimTextLineCharacter {
        VimTextLineCharacter(
            globalOffset: offset,
            minX: 0,
            centerX: 0,
            maxX: 0,
            centerY: 0,
            height: 0
        )
    }
}

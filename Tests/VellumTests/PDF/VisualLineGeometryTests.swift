import AppKit
import Testing
@testable import Vellum

@Suite("Visual line geometry")
struct VisualLineGeometryTests {
    @Test
    func pageIndexFindsContainingPageAndClampsPastEndToLastPage() {
        #expect(VisualLineGeometry.pageIndex(containing: 0, pageStarts: [0, 10, 25]) == 0)
        #expect(VisualLineGeometry.pageIndex(containing: 10, pageStarts: [0, 10, 25]) == 1)
        #expect(VisualLineGeometry.pageIndex(containing: 30, pageStarts: [0, 10, 25]) == 1)
        #expect(VisualLineGeometry.pageIndex(containing: 0, pageStarts: [0]) == nil)
    }

    @Test
    func activeCharacterOffsetTracksForwardAndBackwardSelectionExtent() {
        #expect(VisualLineGeometry.activeCharacterOffset(extentOffset: 8, anchorOffset: 3, totalLength: 20) == 7)
        #expect(VisualLineGeometry.activeCharacterOffset(extentOffset: 2, anchorOffset: 3, totalLength: 20) == 2)
        #expect(VisualLineGeometry.activeCharacterOffset(extentOffset: 30, anchorOffset: 3, totalLength: 20) == 19)
        #expect(VisualLineGeometry.activeCharacterOffset(extentOffset: -5, anchorOffset: 3, totalLength: 20) == 0)
    }

    @Test
    func splitVisualLineSegmentsBreaksLargeHorizontalGaps() {
        let segments = VisualLineGeometry.splitVisualLineSegments([
            character(offset: 0, minX: 0, maxX: 10),
            character(offset: 1, minX: 12, maxX: 22),
            character(offset: 2, minX: 120, maxX: 130)
        ])

        #expect(segments.count == 2)
        #expect(segments[0].map(\VimTextLineCharacter.globalOffset) == [0, 1])
        #expect(segments[1].map(\VimTextLineCharacter.globalOffset) == [2])
    }

    @Test
    func lineIndexPrefersCaretYThenXDistance() {
        let upper = line(page: 0, start: 0, y: 200, minX: 200, maxX: 260)
        let lower = line(page: 0, start: 10, y: 100, minX: 0, maxX: 60)
        let caret = VimTextCaret(
            offset: 4,
            pageIndex: 0,
            slotIndex: 0,
            point: NSPoint(x: 20, y: 0),
            lineMidY: 199.8
        )

        #expect(VisualLineGeometry.lineIndex(for: caret, fallbackOffset: 12, in: [lower, upper]) == 1)
    }

    @Test
    func bestTargetLinePrefersClosestVerticalThenXDistance() {
        let current = line(page: 0, start: 0, y: 200, minX: 0, maxX: 50)
        let closerButFarX = line(page: 0, start: 10, y: 170, minX: 200, maxX: 250)
        let fartherButNearX = line(page: 0, start: 20, y: 130, minX: 0, maxX: 50)

        #expect(VisualLineGeometry.bestTargetLine(
            from: current,
            candidates: [fartherButNearX, closerButFarX],
            preferredX: 20
        )?.startOffset == 10)
    }

    @Test
    func edgeLineChoosesNearestPreferredXOnTopOrBottomRow() {
        let topLeft = line(page: 0, start: 0, y: 200, minX: 0, maxX: 50)
        let topRight = line(page: 0, start: 10, y: 201, minX: 100, maxX: 150)
        let bottom = line(page: 0, start: 20, y: 100, minX: 30, maxX: 80)

        #expect(VisualLineGeometry.edgeLine(
            in: [bottom, topLeft, topRight],
            edge: .top,
            preferredX: 120
        )?.startOffset == 10)
        #expect(VisualLineGeometry.edgeLine(
            in: [bottom, topLeft, topRight],
            edge: .bottom,
            preferredX: 120
        )?.startOffset == 20)
    }

    @Test
    func slotHelpersMapInsertionOffsetsPointsAndOffsets() {
        let textLine = line(page: 0, start: 10, y: 100, minX: 0, maxX: 30)

        #expect(VisualLineGeometry.slotIndex(forInsertionOffset: 11, preferTrailingEdge: false, in: textLine) == 1)
        #expect(VisualLineGeometry.slotIndex(forInsertionOffset: 12, preferTrailingEdge: true, in: textLine) == 2)
        #expect(VisualLineGeometry.pointForSlot(0, in: textLine) == NSPoint(x: 0, y: 100))
        #expect(VisualLineGeometry.pointForSlot(3, in: textLine) == NSPoint(x: 30, y: 100))
        #expect(VisualLineGeometry.offsetForSlot(0, in: textLine) == 10)
        #expect(VisualLineGeometry.offsetForSlot(3, in: textLine) == 13)
    }

    @Test
    func targetCaretClampsPreferredXAndBreaksTiesTowardTrailingOffset() {
        let textLine = line(page: 2, start: 40, y: 100, minX: 0, maxX: 30)

        #expect(VisualLineGeometry.targetCaret(in: textLine, preferredX: -50)?.slotIndex == 0)
        #expect(VisualLineGeometry.targetCaret(in: textLine, preferredX: 50)?.slotIndex == 3)
        #expect(VisualLineGeometry.targetCaret(in: textLine, preferredX: 15)?.slotIndex == 2)
    }

    private func character(
        offset: Int,
        minX: CGFloat,
        maxX: CGFloat,
        centerY: CGFloat = 100,
        height: CGFloat = 10
    ) -> VimTextLineCharacter {
        VimTextLineCharacter(
            globalOffset: offset,
            minX: minX,
            centerX: (minX + maxX) / 2,
            maxX: maxX,
            centerY: centerY,
            height: height
        )
    }

    private func line(
        page: Int,
        start: Int,
        y: CGFloat,
        minX: CGFloat,
        maxX: CGFloat
    ) -> VimTextLine {
        let width = (maxX - minX) / 3
        let characters = (0..<3).map { index in
            character(
                offset: start + index,
                minX: minX + CGFloat(index) * width,
                maxX: minX + CGFloat(index + 1) * width,
                centerY: y
            )
        }

        return VimTextLine(
            pageIndex: page,
            startOffset: start,
            endOffset: start + characters.count,
            midY: y,
            characters: characters
        )
    }
}

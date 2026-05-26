import AppKit

enum VisualLineGeometry {
    enum Edge {
        case top
        case bottom
    }

    static func lineIndex(for caret: VimTextCaret?, fallbackOffset: Int, in lines: [VimTextLine]) -> Int? {
        guard !lines.isEmpty else { return nil }

        if let caret,
           let exactPageLine = lines.indices.min(by: { lhs, rhs in
               let lhsLine = lines[lhs]
               let rhsLine = lines[rhs]
               let lhsY = abs(lhsLine.midY - caret.lineMidY)
               let rhsY = abs(rhsLine.midY - caret.lineMidY)
               if abs(lhsY - rhsY) > 0.5 {
                   return lhsY < rhsY
               }
               return lineDistanceToX(caret.point.x, lhsLine) < lineDistanceToX(caret.point.x, rhsLine)
           }) {
            return exactPageLine
        }

        if let exactOffsetLine = lines.firstIndex(where: { line in
            line.characters.contains { $0.globalOffset == fallbackOffset }
        }) {
            return exactOffsetLine
        }

        return lines.indices.min { lhs, rhs in
            distance(from: fallbackOffset, to: lines[lhs]) < distance(from: fallbackOffset, to: lines[rhs])
        }
    }

    static func compareVisualPosition(_ lhs: VimTextCaretPosition, _ rhs: VimTextCaretPosition) -> Int {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex ? -1 : 1
        }

        if lhs.lineIndex != rhs.lineIndex {
            return lhs.lineIndex < rhs.lineIndex ? -1 : 1
        }

        if lhs.slotIndex != rhs.slotIndex {
            return lhs.slotIndex < rhs.slotIndex ? -1 : 1
        }

        return 0
    }

    static func sameVisualCaret(_ lhs: VimTextCaret?, _ rhs: VimTextCaret?) -> Bool {
        guard let lhs, let rhs else { return false }

        return lhs.pageIndex == rhs.pageIndex
            && lhs.slotIndex == rhs.slotIndex
            && abs(lhs.lineMidY - rhs.lineMidY) < 0.5
    }

    static func averageCharacterHeight(in line: VimTextLine) -> CGFloat {
        guard !line.characters.isEmpty else { return 0 }
        return line.characters.reduce(CGFloat(0)) { $0 + $1.height } / CGFloat(line.characters.count)
    }

    static func distance(from offset: Int, to line: VimTextLine) -> Int {
        if offset < line.startOffset {
            return line.startOffset - offset
        }

        if offset >= line.endOffset {
            return offset - line.endOffset + 1
        }

        return 0
    }

    static func activeCharacterOffset(extentOffset: Int, anchorOffset: Int, totalLength: Int) -> Int {
        let offset = extentOffset >= anchorOffset ? extentOffset - 1 : extentOffset
        return min(max(offset, 0), max(0, totalLength - 1))
    }

    static func pageIndex(containing globalOffset: Int, pageStarts: [Int]) -> Int? {
        guard pageStarts.count > 1 else { return nil }

        for index in 0..<(pageStarts.count - 1) {
            if globalOffset >= pageStarts[index], globalOffset < pageStarts[index + 1] {
                return index
            }
        }

        return pageStarts.count >= 2 ? pageStarts.count - 2 : nil
    }

    static func splitVisualLineSegments(_ characters: [VimTextLineCharacter]) -> [[VimTextLineCharacter]] {
        guard !characters.isEmpty else { return [] }

        let averageWidth = characters.reduce(CGFloat(0)) { $0 + max(1, $1.maxX - $1.minX) } / CGFloat(characters.count)
        let gapThreshold = max(28, averageWidth * 5.5)
        var segments: [[VimTextLineCharacter]] = []
        var current: [VimTextLineCharacter] = []
        var previous: VimTextLineCharacter?

        for character in characters {
            if let previous,
               character.minX - previous.maxX > gapThreshold,
               !current.isEmpty {
                segments.append(current)
                current = []
            }

            current.append(character)
            previous = character
        }

        if !current.isEmpty {
            segments.append(current)
        }

        return segments
    }

    static func bestTargetLine(
        from currentLine: VimTextLine,
        candidates: [VimTextLine],
        preferredX: CGFloat
    ) -> VimTextLine? {
        candidates.min { lhs, rhs in
            let lhsVerticalDistance = abs(lhs.midY - currentLine.midY)
            let rhsVerticalDistance = abs(rhs.midY - currentLine.midY)

            if abs(lhsVerticalDistance - rhsVerticalDistance) > max(1, averageCharacterHeight(in: currentLine) * 0.25) {
                return lhsVerticalDistance < rhsVerticalDistance
            }

            let lhsXDistance = lineDistanceToX(preferredX, lhs)
            let rhsXDistance = lineDistanceToX(preferredX, rhs)
            if abs(lhsXDistance - rhsXDistance) > 0.5 {
                return lhsXDistance < rhsXDistance
            }

            return lhs.characters.first?.minX ?? 0 < rhs.characters.first?.minX ?? 0
        }
    }

    static func edgeLine(in lines: [VimTextLine], edge: Edge, preferredX: CGFloat) -> VimTextLine? {
        guard !lines.isEmpty else { return nil }

        let edgeY: CGFloat
        switch edge {
        case .top:
            edgeY = lines.map(\.midY).max() ?? 0
        case .bottom:
            edgeY = lines.map(\.midY).min() ?? 0
        }

        let rowTolerance = max(2, (lines.map { averageCharacterHeight(in: $0) }.max() ?? 0) * 0.7)
        let edgeLines = lines.filter { abs($0.midY - edgeY) <= rowTolerance }
        return edgeLines.min { lhs, rhs in
            lineDistanceToX(preferredX, lhs) < lineDistanceToX(preferredX, rhs)
        }
    }

    static func lineDistanceToX(_ x: CGFloat, _ line: VimTextLine) -> CGFloat {
        guard let first = line.characters.first,
              let last = line.characters.last else { return .greatestFiniteMagnitude }

        if x < first.minX {
            return first.minX - x
        }

        if x > last.maxX {
            return x - last.maxX
        }

        return 0
    }

    static func caretX(
        near globalOffset: Int,
        in line: VimTextLine,
        selectionIsForward: Bool
    ) -> CGFloat? {
        guard let nearest = line.characters.min(by: {
            abs($0.globalOffset - globalOffset) < abs($1.globalOffset - globalOffset)
        }) else { return nil }

        return selectionIsForward ? nearest.maxX : nearest.minX
    }

    static func targetCaret(in line: VimTextLine, preferredX: CGFloat) -> VimTextCaret? {
        let slots = (0...line.characters.count).map { slotIndex in
            let point = pointForSlot(slotIndex, in: line)
            return VimTextCaret(
                offset: offsetForSlot(slotIndex, in: line),
                pageIndex: line.pageIndex,
                slotIndex: slotIndex,
                point: point,
                lineMidY: line.midY
            )
        }

        guard !slots.isEmpty else { return nil }

        let clampedX = min(
            max(preferredX, line.characters.first?.minX ?? preferredX),
            line.characters.last?.maxX ?? preferredX
        )

        return slots.min { lhs, rhs in
            let lhsDistance = abs(lhs.point.x - clampedX)
            let rhsDistance = abs(rhs.point.x - clampedX)

            if abs(lhsDistance - rhsDistance) < 0.001 {
                return lhs.offset > rhs.offset
            }

            return lhsDistance < rhsDistance
        }
    }

    static func closestSlotIndex(to x: CGFloat, in line: VimTextLine, fallbackSlot: Int) -> Int {
        guard !line.characters.isEmpty else { return 0 }

        let slots = (0...line.characters.count).map { slotIndex in
            (slotIndex: slotIndex, point: pointForSlot(slotIndex, in: line))
        }

        return slots.min { lhs, rhs in
            let lhsDistance = abs(lhs.point.x - x)
            let rhsDistance = abs(rhs.point.x - x)

            if abs(lhsDistance - rhsDistance) < 0.001 {
                return abs(lhs.slotIndex - fallbackSlot) < abs(rhs.slotIndex - fallbackSlot)
            }

            return lhsDistance < rhsDistance
        }?.slotIndex ?? fallbackSlot
    }

    static func slotIndex(
        forInsertionOffset insertionOffset: Int,
        preferTrailingEdge: Bool,
        in line: VimTextLine
    ) -> Int {
        guard !line.characters.isEmpty else { return 0 }

        if preferTrailingEdge,
           let previousIndex = line.characters.lastIndex(where: { $0.globalOffset < insertionOffset }) {
            return min(line.characters.count, previousIndex + 1)
        }

        if let exactIndex = line.characters.firstIndex(where: { $0.globalOffset >= insertionOffset }) {
            return exactIndex
        }

        return line.characters.count
    }

    static func pointForSlot(_ slotIndex: Int, in line: VimTextLine) -> NSPoint {
        guard !line.characters.isEmpty else {
            return NSPoint(x: 0, y: line.midY)
        }

        if slotIndex <= 0, let first = line.characters.first {
            return NSPoint(x: first.minX, y: first.centerY)
        }

        if slotIndex >= line.characters.count, let last = line.characters.last {
            return NSPoint(x: last.maxX, y: last.centerY)
        }

        let previous = line.characters[slotIndex - 1]
        let next = line.characters[slotIndex]
        return NSPoint(
            x: max(previous.maxX, next.minX),
            y: (previous.centerY + next.centerY) / 2
        )
    }

    static func offsetForSlot(_ slotIndex: Int, in line: VimTextLine) -> Int {
        guard !line.characters.isEmpty else { return line.startOffset }

        if slotIndex <= 0 {
            return line.characters[0].globalOffset
        }

        if slotIndex >= line.characters.count {
            return line.characters[line.characters.count - 1].globalOffset + 1
        }

        return line.characters[slotIndex].globalOffset
    }
}

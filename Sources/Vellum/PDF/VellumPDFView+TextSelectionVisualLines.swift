@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
    func verticalSelectionCaret(
        from extentCaret: VimTextCaret?,
        fallbackExtentOffset: Int,
        anchorOffset: Int,
        anchorCaret: VimTextCaret?,
        direction: Int,
        preferredX: CGFloat?,
        pageStarts: [Int]
    ) -> (caret: VimTextCaret, preferredX: CGFloat)? {
        guard let document,
              let totalLength = pageStarts.last,
              totalLength > 0 else { return nil }

        let fallbackActiveOffset = activeCharacterOffset(
            extentOffset: fallbackExtentOffset,
            anchorOffset: anchorOffset,
            totalLength: totalLength
        )
        let activeCaret = extentCaret ?? textCaret(
            atInsertionOffset: fallbackExtentOffset,
            preferTrailingEdge: fallbackExtentOffset >= anchorOffset,
            pageStarts: pageStarts
        )
        let pageIndex = activeCaret?.pageIndex
            ?? pageIndex(containing: fallbackActiveOffset, pageStarts: pageStarts)
        guard let pageIndex else { return nil }

        let lines = textLines(onPageAt: pageIndex, pageStarts: pageStarts)
        guard let currentLineIndex = lineIndex(for: activeCaret, fallbackOffset: fallbackActiveOffset, in: lines) else { return nil }

        let currentX = preferredX ?? activeCaret?.point.x ?? caretX(
            near: fallbackActiveOffset,
            in: lines[currentLineIndex],
            selectionIsForward: fallbackExtentOffset >= anchorOffset,
            pageStarts: pageStarts
        )
        let currentLine = lines[currentLineIndex]
        guard let targetLine = targetLine(
            from: currentLine,
            direction: direction,
            document: document,
            pageStarts: pageStarts,
            preferredX: currentX
        ) else { return nil }

        guard var targetCaret = targetCaret(in: targetLine, preferredX: currentX) else { return nil }
        targetCaret = adjustedTargetCaret(
            targetCaret,
            targetLine: targetLine,
            anchorCaret: anchorCaret,
            pageStarts: pageStarts
        )
        return (targetCaret, currentX)
    }

    func lineIndex(for caret: VimTextCaret?, fallbackOffset: Int, in lines: [VimTextLine]) -> Int? {
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

    func visualCaretPosition(
        for caret: VimTextCaret,
        pageStarts: [Int]
    ) -> VimTextCaretPosition? {
        let lines = textLines(onPageAt: caret.pageIndex, pageStarts: pageStarts)
        guard let lineIndex = lineIndex(for: caret, fallbackOffset: caret.offset, in: lines) else { return nil }
        let line = lines[lineIndex]
        let slotIndex = min(
            max(closestSlotIndex(to: caret.point.x, in: line, fallbackSlot: caret.slotIndex), 0),
            line.characters.count
        )

        return VimTextCaretPosition(
            pageIndex: caret.pageIndex,
            lineIndex: lineIndex,
            slotIndex: slotIndex
        )
    }

    func compareVisualPosition(_ lhs: VimTextCaretPosition, _ rhs: VimTextCaretPosition) -> Int {
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

    func sameVisualCaret(_ lhs: VimTextCaret?, _ rhs: VimTextCaret?) -> Bool {
        guard let lhs, let rhs else { return false }

        return lhs.pageIndex == rhs.pageIndex
            && lhs.slotIndex == rhs.slotIndex
            && abs(lhs.lineMidY - rhs.lineMidY) < 0.5
    }

    func averageCharacterHeight(in line: VimTextLine) -> CGFloat {
        guard !line.characters.isEmpty else { return 0 }
        return line.characters.reduce(CGFloat(0)) { $0 + $1.height } / CGFloat(line.characters.count)
    }

    func distance(from offset: Int, to line: VimTextLine) -> Int {
        if offset < line.startOffset {
            return line.startOffset - offset
        }

        if offset >= line.endOffset {
            return offset - line.endOffset + 1
        }

        return 0
    }

    func activeCharacterOffset(extentOffset: Int, anchorOffset: Int, totalLength: Int) -> Int {
        let offset = extentOffset >= anchorOffset ? extentOffset - 1 : extentOffset
        return min(max(offset, 0), max(0, totalLength - 1))
    }

    func pageIndex(containing globalOffset: Int, pageStarts: [Int]) -> Int? {
        guard pageStarts.count > 1 else { return nil }

        for index in 0..<(pageStarts.count - 1) {
            if globalOffset >= pageStarts[index], globalOffset < pageStarts[index + 1] {
                return index
            }
        }

        return pageStarts.count >= 2 ? pageStarts.count - 2 : nil
    }

    func textLines(onPageAt pageIndex: Int, pageStarts: [Int]) -> [VimTextLine] {
        guard let page = document?.page(at: pageIndex),
              pageIndex + 1 < pageStarts.count else { return [] }

        let pageStart = pageStarts[pageIndex]
        let pageText = page.string as NSString?
        var characters: [VimTextLineCharacter] = []
        for characterIndex in 0..<page.numberOfCharacters {
            guard !isNewlineCharacter(at: characterIndex, in: pageText) else { continue }

            let bounds = page.characterBounds(at: characterIndex)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            characters.append(
                VimTextLineCharacter(
                    globalOffset: pageStart + characterIndex,
                    minX: bounds.minX,
                    centerX: bounds.midX,
                    maxX: bounds.maxX,
                    centerY: bounds.midY,
                    height: bounds.height
                )
            )
        }

        let sortedCharacters = characters.sorted {
            if abs($0.centerY - $1.centerY) > 2 {
                return $0.centerY > $1.centerY
            }
            return $0.centerX < $1.centerX
        }

        var grouped: [[VimTextLineCharacter]] = []
        for character in sortedCharacters {
            if let last = grouped.indices.last,
               let reference = grouped[last].first {
                let threshold = max(2.0, max(reference.height, character.height) * 0.65)
                if abs(reference.centerY - character.centerY) <= threshold {
                    grouped[last].append(character)
                    continue
                }
            }
            grouped.append([character])
        }

        return grouped.flatMap { group in
            splitVisualLineSegments(group.sorted { $0.centerX < $1.centerX }).compactMap { lineCharacters in
                guard let start = lineCharacters.map(\.globalOffset).min(),
                      let end = lineCharacters.map(\.globalOffset).max().map({ $0 + 1 }) else {
                    return nil
                }

                let midY = lineCharacters.reduce(CGFloat(0)) { $0 + $1.centerY } / CGFloat(lineCharacters.count)
                return VimTextLine(
                    pageIndex: pageIndex,
                    startOffset: start,
                    endOffset: end,
                    midY: midY,
                    characters: lineCharacters
                )
            }
        }
    }

    func splitVisualLineSegments(_ characters: [VimTextLineCharacter]) -> [[VimTextLineCharacter]] {
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

    func targetLine(
        from currentLine: VimTextLine,
        direction: Int,
        document: PDFDocument,
        pageStarts: [Int],
        preferredX: CGFloat
    ) -> VimTextLine? {
        let currentHeight = averageCharacterHeight(in: currentLine)
        let sameRowThreshold = max(2, currentHeight * 0.7)
        let currentPageLines = textLines(onPageAt: currentLine.pageIndex, pageStarts: pageStarts)

        let samePageCandidates = currentPageLines.filter { candidate in
            if direction > 0 {
                return currentLine.midY - candidate.midY > sameRowThreshold
            }

            return candidate.midY - currentLine.midY > sameRowThreshold
        }

        if let line = bestTargetLine(from: currentLine, candidates: samePageCandidates, preferredX: preferredX) {
            return line
        }

        if direction > 0 {
            for nextPageIndex in (currentLine.pageIndex + 1)..<document.pageCount {
                let lines = textLines(onPageAt: nextPageIndex, pageStarts: pageStarts)
                if let line = edgeLine(in: lines, edge: .top, preferredX: preferredX) {
                    return line
                }
            }
        } else if currentLine.pageIndex > 0 {
            for previousPageIndex in stride(from: currentLine.pageIndex - 1, through: 0, by: -1) {
                let lines = textLines(onPageAt: previousPageIndex, pageStarts: pageStarts)
                if let line = edgeLine(in: lines, edge: .bottom, preferredX: preferredX) {
                    return line
                }
            }
        }

        return nil
    }

    enum VisualLineEdge {
        case top
        case bottom
    }

    func bestTargetLine(
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

    func edgeLine(in lines: [VimTextLine], edge: VisualLineEdge, preferredX: CGFloat) -> VimTextLine? {
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

    func lineDistanceToX(_ x: CGFloat, _ line: VimTextLine) -> CGFloat {
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

    func caretX(
        near globalOffset: Int,
        in line: VimTextLine,
        selectionIsForward: Bool,
        pageStarts: [Int]
    ) -> CGFloat {
        if let nearest = line.characters.min(by: {
            abs($0.globalOffset - globalOffset) < abs($1.globalOffset - globalOffset)
        }) {
            return selectionIsForward ? nearest.maxX : nearest.minX
        }

        return characterCenterX(globalOffset: globalOffset, pageStarts: pageStarts)
    }

    func targetCaret(
        in line: VimTextLine,
        preferredX: CGFloat
    ) -> VimTextCaret? {
        guard document?.page(at: line.pageIndex) != nil else { return nil }

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

    func adjustedTargetCaret(
        _ caret: VimTextCaret,
        targetLine: VimTextLine,
        anchorCaret: VimTextCaret?,
        pageStarts: [Int]
    ) -> VimTextCaret {
        guard let anchorCaret,
              let anchorPosition = visualCaretPosition(for: anchorCaret, pageStarts: pageStarts),
              let targetPosition = visualCaretPosition(for: caret, pageStarts: pageStarts) else {
            return caret
        }

        let comparison = compareVisualPosition(anchorPosition, targetPosition)
        var slotIndex = caret.slotIndex

        if comparison < 0, slotIndex == 0, !targetLine.characters.isEmpty {
            slotIndex = 1
        } else if comparison > 0, slotIndex == targetLine.characters.count, !targetLine.characters.isEmpty {
            slotIndex = max(0, targetLine.characters.count - 1)
        }

        guard slotIndex != caret.slotIndex else { return caret }

        let point = pointForSlot(slotIndex, in: targetLine)
        return VimTextCaret(
            offset: offsetForSlot(slotIndex, in: targetLine),
            pageIndex: targetLine.pageIndex,
            slotIndex: slotIndex,
            point: point,
            lineMidY: targetLine.midY
        )
    }

    func closestSlotIndex(to x: CGFloat, in line: VimTextLine, fallbackSlot: Int) -> Int {
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

    func slotIndex(
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

    func pointForSlot(_ slotIndex: Int, in line: VimTextLine) -> NSPoint {
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

    func offsetForSlot(_ slotIndex: Int, in line: VimTextLine) -> Int {
        guard !line.characters.isEmpty else { return line.startOffset }

        if slotIndex <= 0 {
            return line.characters[0].globalOffset
        }

        if slotIndex >= line.characters.count {
            return line.characters[line.characters.count - 1].globalOffset + 1
        }

        return line.characters[slotIndex].globalOffset
    }

    func characterCenterX(globalOffset: Int, pageStarts: [Int]) -> CGFloat {
        guard let pageIndex = pageIndex(containing: globalOffset, pageStarts: pageStarts),
              let page = document?.page(at: pageIndex) else { return 0 }

        let localOffset = globalOffset - pageStarts[pageIndex]
        return page.characterBounds(at: localOffset).midX
    }
}

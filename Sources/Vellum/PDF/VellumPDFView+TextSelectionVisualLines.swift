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
        VisualLineGeometry.lineIndex(for: caret, fallbackOffset: fallbackOffset, in: lines)
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
        VisualLineGeometry.compareVisualPosition(lhs, rhs)
    }

    func sameVisualCaret(_ lhs: VimTextCaret?, _ rhs: VimTextCaret?) -> Bool {
        VisualLineGeometry.sameVisualCaret(lhs, rhs)
    }

    func averageCharacterHeight(in line: VimTextLine) -> CGFloat {
        VisualLineGeometry.averageCharacterHeight(in: line)
    }

    func distance(from offset: Int, to line: VimTextLine) -> Int {
        VisualLineGeometry.distance(from: offset, to: line)
    }

    func activeCharacterOffset(extentOffset: Int, anchorOffset: Int, totalLength: Int) -> Int {
        VisualLineGeometry.activeCharacterOffset(
            extentOffset: extentOffset,
            anchorOffset: anchorOffset,
            totalLength: totalLength
        )
    }

    func pageIndex(containing globalOffset: Int, pageStarts: [Int]) -> Int? {
        VisualLineGeometry.pageIndex(containing: globalOffset, pageStarts: pageStarts)
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
            VisualLineGeometry.splitVisualLineSegments(group.sorted { $0.centerX < $1.centerX }).compactMap { lineCharacters in
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
        VisualLineGeometry.splitVisualLineSegments(characters)
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

    func bestTargetLine(
        from currentLine: VimTextLine,
        candidates: [VimTextLine],
        preferredX: CGFloat
    ) -> VimTextLine? {
        VisualLineGeometry.bestTargetLine(from: currentLine, candidates: candidates, preferredX: preferredX)
    }

    func edgeLine(in lines: [VimTextLine], edge: VisualLineGeometry.Edge, preferredX: CGFloat) -> VimTextLine? {
        VisualLineGeometry.edgeLine(in: lines, edge: edge, preferredX: preferredX)
    }

    func lineDistanceToX(_ x: CGFloat, _ line: VimTextLine) -> CGFloat {
        VisualLineGeometry.lineDistanceToX(x, line)
    }

    func caretX(
        near globalOffset: Int,
        in line: VimTextLine,
        selectionIsForward: Bool,
        pageStarts: [Int]
    ) -> CGFloat {
        VisualLineGeometry.caretX(
            near: globalOffset,
            in: line,
            selectionIsForward: selectionIsForward
        ) ?? characterCenterX(globalOffset: globalOffset, pageStarts: pageStarts)
    }

    func targetCaret(
        in line: VimTextLine,
        preferredX: CGFloat
    ) -> VimTextCaret? {
        guard document?.page(at: line.pageIndex) != nil else { return nil }

        return VisualLineGeometry.targetCaret(in: line, preferredX: preferredX)
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
        VisualLineGeometry.closestSlotIndex(to: x, in: line, fallbackSlot: fallbackSlot)
    }

    func slotIndex(
        forInsertionOffset insertionOffset: Int,
        preferTrailingEdge: Bool,
        in line: VimTextLine
    ) -> Int {
        VisualLineGeometry.slotIndex(
            forInsertionOffset: insertionOffset,
            preferTrailingEdge: preferTrailingEdge,
            in: line
        )
    }

    func pointForSlot(_ slotIndex: Int, in line: VimTextLine) -> NSPoint {
        VisualLineGeometry.pointForSlot(slotIndex, in: line)
    }

    func offsetForSlot(_ slotIndex: Int, in line: VimTextLine) -> Int {
        VisualLineGeometry.offsetForSlot(slotIndex, in: line)
    }

    func characterCenterX(globalOffset: Int, pageStarts: [Int]) -> CGFloat {
        guard let pageIndex = pageIndex(containing: globalOffset, pageStarts: pageStarts),
              let page = document?.page(at: pageIndex) else { return 0 }

        let localOffset = globalOffset - pageStarts[pageIndex]
        return page.characterBounds(at: localOffset).midX
    }
}

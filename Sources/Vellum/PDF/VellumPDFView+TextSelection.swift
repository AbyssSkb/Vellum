@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    @discardableResult
    func vimNavigateTextSelection(_ key: String) -> Bool {
        let key = key.lowercased()
        guard ["h", "j", "k", "l", "w", "b", "e"].contains(key),
              let document,
              hasNavigableTextSelection else {
            return false
        }

        let pageStarts = textPageStarts(in: document)
        guard let totalLength = pageStarts.last, totalLength > 0 else { return false }

        if textSelectionNavigationState == nil {
            guard let range = currentSelectionCharacterRange(pageStarts: pageStarts) else { return false }
            textSelectionNavigationState = VimTextSelectionNavigationState(
                anchorOffset: range.start,
                extentOffset: range.end,
                preferredX: nil,
                anchorCaret: textCaret(
                    atInsertionOffset: range.start,
                    preferTrailingEdge: false,
                    pageStarts: pageStarts
                ),
                extentCaret: textCaret(
                    atInsertionOffset: range.end,
                    preferTrailingEdge: true,
                    pageStarts: pageStarts
                )
            )
        }

        guard var state = textSelectionNavigationState else { return false }
        var nextExtent: Int?
        var nextExtentCaret: VimTextCaret?
        var movementDirection = 0
        var scrollCaretAfterSelection: VimTextCaret?
        var useVisualSelection = false

        switch key {
        case "h":
            nextExtent = state.extentOffset - 1
            movementDirection = -1
            state.preferredX = nil
        case "l":
            nextExtent = state.extentOffset + 1
            movementDirection = 1
            state.preferredX = nil
        case "b":
            nextExtent = wordBackwardOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
            movementDirection = -1
            state.preferredX = nil
        case "w":
            nextExtent = wordForwardOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
            movementDirection = 1
            state.preferredX = nil
        case "e":
            nextExtent = wordEndOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
            movementDirection = 1
            state.preferredX = nil
        case "j", "k":
            useVisualSelection = true
            let verticalMove = verticalSelectionCaret(
                from: state.extentCaret,
                fallbackExtentOffset: state.extentOffset,
                anchorOffset: state.anchorOffset,
                anchorCaret: state.anchorCaret,
                direction: key == "j" ? 1 : -1,
                preferredX: state.preferredX,
                pageStarts: pageStarts
            )
            nextExtent = verticalMove?.caret.offset
            nextExtentCaret = verticalMove?.caret
            scrollCaretAfterSelection = verticalMove?.caret
            state.preferredX = verticalMove?.preferredX ?? state.preferredX
            movementDirection = key == "j" ? 1 : -1
        default:
            return false
        }

        guard var extent = nextExtent else { return false }
        extent = min(max(extent, 0), totalLength)
        if !useVisualSelection, extent == state.anchorOffset {
            extent = min(max(state.anchorOffset + movementDirection, 0), totalLength)
        }
        if useVisualSelection {
            guard nextExtentCaret != nil,
                  !sameVisualCaret(nextExtentCaret, state.anchorCaret) else { return true }
        } else {
            guard extent != state.anchorOffset else { return true }
        }

        state.extentOffset = extent
        state.extentCaret = nextExtentCaret ?? textCaret(
            atInsertionOffset: state.extentOffset,
            preferTrailingEdge: state.extentOffset >= state.anchorOffset,
            pageStarts: pageStarts
        )

        let didApplySelection = useVisualSelection
            ? applyVisualTextSelection(anchorCaret: state.anchorCaret, extentCaret: state.extentCaret, pageStarts: pageStarts)
                || applyTextSelection(
                    anchorOffset: state.anchorOffset,
                    extentOffset: state.extentOffset,
                    pageStarts: pageStarts,
                    scrollToEndpoint: scrollCaretAfterSelection == nil
                )
            : applyTextSelection(
                anchorOffset: state.anchorOffset,
                extentOffset: state.extentOffset,
                pageStarts: pageStarts,
                scrollToEndpoint: scrollCaretAfterSelection == nil
            )

        guard didApplySelection else {
            textSelectionNavigationState = nil
            return false
        }

        if let scrollCaretAfterSelection {
            scrollTextCaretToVisible(scrollCaretAfterSelection)
        }

        textSelectionNavigationState = state
        return true
    }

    func currentSelectionCharacterRange(pageStarts: [Int]) -> (start: Int, end: Int)? {
        guard let selection = currentSelection else { return nil }

        var selectedRanges: [(start: Int, end: Int)] = []
        for page in selection.pages {
            guard let pageIndex = document?.index(for: page),
                  pageIndex != NSNotFound,
                  pageIndex + 1 < pageStarts.count else { continue }

            let pageStart = pageStarts[pageIndex]
            let rangeCount = selection.numberOfTextRanges(on: page)
            for rangeIndex in 0..<rangeCount {
                let range = selection.range(at: rangeIndex, on: page)
                guard range.location != NSNotFound, range.length > 0 else { continue }

                let start = pageStart + range.location
                let end = min(pageStarts[pageIndex + 1], start + range.length)
                guard end > start else { continue }
                selectedRanges.append((start, end))
            }
        }

        if let start = selectedRanges.map(\.start).min(),
           let end = selectedRanges.map(\.end).max(),
           end > start {
            return (start, end)
        }

        var selectedOffsets: [Int] = []
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var pageRects: [Int: [NSRect]] = [:]

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let pageIndex = document?.index(for: page),
                      pageIndex != NSNotFound,
                      pageIndex + 1 < pageStarts.count else { continue }

                let bounds = lineSelection.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                pageRects[pageIndex, default: []].append(bounds.insetBy(dx: -1.5, dy: -2.0))
            }
        }

        for (pageIndex, rects) in pageRects {
            guard let page = document?.page(at: pageIndex) else { continue }
            let pageStart = pageStarts[pageIndex]
            for characterIndex in 0..<page.numberOfCharacters {
                let bounds = page.characterBounds(at: characterIndex)
                guard bounds.width > 0, bounds.height > 0 else { continue }

                let center = NSPoint(x: bounds.midX, y: bounds.midY)
                if rects.contains(where: { rect in rect.contains(center) || rect.intersects(bounds) }) {
                    selectedOffsets.append(pageStart + characterIndex)
                }
            }
        }

        guard let start = selectedOffsets.min(),
              let end = selectedOffsets.max().map({ $0 + 1 }),
              end > start else {
            return selectionStringCharacterRange(selection, pageStarts: pageStarts)
        }

        return (start, end)
    }

    func selectionStringCharacterRange(
        _ selection: PDFSelection,
        pageStarts: [Int]
    ) -> (start: Int, end: Int)? {
        guard let selectedText = selection.string?.nilIfEmpty else { return nil }

        for page in selection.pages {
            guard let pageIndex = document?.index(for: page),
                  pageIndex != NSNotFound,
                  pageIndex < pageStarts.count,
                  let pageText = page.string as NSString? else { continue }

            let range = pageText.range(of: selectedText)
            if range.location != NSNotFound, range.length > 0 {
                let start = pageStarts[pageIndex] + range.location
                return (start, start + range.length)
            }
        }

        guard let document else { return nil }
        let documentText = documentText(in: document) as NSString
        let range = documentText.range(of: selectedText)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return (range.location, range.location + range.length)
    }

    func applyTextSelection(
        anchorOffset: Int,
        extentOffset: Int,
        pageStarts: [Int],
        scrollToEndpoint: Bool = true
    ) -> Bool {
        guard let document else { return false }

        let startOffset = min(anchorOffset, extentOffset)
        let endOffset = max(anchorOffset, extentOffset)
        guard endOffset > startOffset else { return false }

        if let startEndpoint = textSelectionEndpoint(forInclusiveOffset: startOffset, pageStarts: pageStarts),
           let endEndpoint = textSelectionEndpoint(forInclusiveOffset: endOffset - 1, pageStarts: pageStarts),
           let selection = document.selection(
                from: startEndpoint.page,
                atCharacterIndex: startEndpoint.characterIndex,
                to: endEndpoint.page,
                atCharacterIndex: endEndpoint.characterIndex
           ),
           !selection.pages.isEmpty {
            setCurrentSelection(selection, animate: false)
            if scrollToEndpoint {
                scrollTextSelectionEndpointToVisible(
                    anchorOffset: anchorOffset,
                    extentOffset: extentOffset,
                    pageStarts: pageStarts
                )
            }
            needsDisplay = true
            return true
        }

        let selection = PDFSelection()
        for pageIndex in 0..<document.pageCount {
            guard pageIndex + 1 < pageStarts.count,
                  let page = document.page(at: pageIndex) else { continue }

            let pageStart = pageStarts[pageIndex]
            let pageEnd = pageStarts[pageIndex + 1]
            let localStart = max(startOffset, pageStart) - pageStart
            let localEnd = min(endOffset, pageEnd) - pageStart
            guard localEnd > localStart else { continue }

            let range = NSRange(location: localStart, length: localEnd - localStart)
            if let pageSelection = page.selection(for: range) {
                selection.add(pageSelection)
            }
        }

        guard !selection.pages.isEmpty else { return false }
        setCurrentSelection(selection, animate: false)
        if scrollToEndpoint {
            scrollTextSelectionEndpointToVisible(
                anchorOffset: anchorOffset,
                extentOffset: extentOffset,
                pageStarts: pageStarts
            )
        }
        needsDisplay = true
        return true
    }

    func applyVisualTextSelection(
        anchorCaret: VimTextCaret?,
        extentCaret: VimTextCaret?,
        pageStarts: [Int]
    ) -> Bool {
        guard let anchorCaret,
              let extentCaret,
              let document else { return false }

        let anchorPosition = visualCaretPosition(for: anchorCaret, pageStarts: pageStarts)
        let extentPosition = visualCaretPosition(for: extentCaret, pageStarts: pageStarts)
        guard let anchorPosition, let extentPosition else { return false }

        let isForward = compareVisualPosition(anchorPosition, extentPosition) <= 0
        let start = isForward ? anchorPosition : extentPosition
        let end = isForward ? extentPosition : anchorPosition

        let selection = PDFSelection()
        for pageIndex in start.pageIndex...end.pageIndex {
            guard pageIndex + 1 < pageStarts.count,
                  let page = document.page(at: pageIndex) else { continue }

            let lines = textLines(onPageAt: pageIndex, pageStarts: pageStarts)
            guard !lines.isEmpty else { continue }

            let firstLine = pageIndex == start.pageIndex ? start.lineIndex : 0
            let lastLine = pageIndex == end.pageIndex ? end.lineIndex : lines.count - 1
            guard firstLine <= lastLine,
                  firstLine >= 0,
                  lastLine < lines.count else { continue }

            for lineIndex in firstLine...lastLine {
                let line = lines[lineIndex]
                let startSlot = pageIndex == start.pageIndex && lineIndex == start.lineIndex
                    ? start.slotIndex
                    : 0
                let endSlot = pageIndex == end.pageIndex && lineIndex == end.lineIndex
                    ? end.slotIndex
                    : line.characters.count

                addVisualLineSelection(
                    line: line,
                    startSlot: startSlot,
                    endSlot: endSlot,
                    page: page,
                    pageStart: pageStarts[pageIndex],
                    to: selection
                )
            }
        }

        guard !selection.pages.isEmpty else { return false }
        setCurrentSelection(selection, animate: false)
        scrollTextCaretToVisible(extentCaret)
        needsDisplay = true
        return true
    }

    func addVisualLineSelection(
        line: VimTextLine,
        startSlot rawStartSlot: Int,
        endSlot rawEndSlot: Int,
        page: PDFPage,
        pageStart: Int,
        to selection: PDFSelection
    ) {
        let startSlot = min(max(rawStartSlot, 0), line.characters.count)
        let endSlot = min(max(rawEndSlot, 0), line.characters.count)
        guard endSlot > startSlot else { return }

        let offsets = line.characters[startSlot..<endSlot]
            .map { $0.globalOffset - pageStart }
            .sorted()
        guard var runStart = offsets.first else { return }
        var previous = runStart

        for offset in offsets.dropFirst() {
            if offset == previous + 1 {
                previous = offset
                continue
            }

            addPageSelection(page: page, start: runStart, end: previous + 1, to: selection)
            runStart = offset
            previous = offset
        }

        addPageSelection(page: page, start: runStart, end: previous + 1, to: selection)
    }

    func addPageSelection(page: PDFPage, start: Int, end: Int, to selection: PDFSelection) {
        guard end > start else { return }

        let range = NSRange(location: start, length: end - start)
        if let pageSelection = page.selection(for: range) {
            selection.add(pageSelection)
        }
    }

    func textSelectionEndpoint(
        forInclusiveOffset offset: Int,
        pageStarts: [Int]
    ) -> (page: PDFPage, characterIndex: Int)? {
        guard let document,
              let totalLength = pageStarts.last,
              totalLength > 0 else { return nil }

        let clampedOffset = min(max(offset, 0), totalLength - 1)
        guard let pageIndex = pageIndex(containing: clampedOffset, pageStarts: pageStarts),
              let page = document.page(at: pageIndex),
              page.numberOfCharacters > 0 else { return nil }

        let characterIndex = min(
            max(clampedOffset - pageStarts[pageIndex], 0),
            max(0, page.numberOfCharacters - 1)
        )
        return (page, characterIndex)
    }

    func textCaret(
        atInsertionOffset offset: Int,
        preferTrailingEdge: Bool,
        pageStarts: [Int]
    ) -> VimTextCaret? {
        guard let totalLength = pageStarts.last, totalLength > 0 else { return nil }

        let insertionOffset = min(max(offset, 0), totalLength)
        let candidateOffset: Int
        let preferPrevious: Bool

        if preferTrailingEdge {
            candidateOffset = max(0, insertionOffset - 1)
            preferPrevious = true
        } else if insertionOffset >= totalLength {
            candidateOffset = totalLength - 1
            preferPrevious = true
        } else {
            candidateOffset = insertionOffset
            preferPrevious = false
        }

        guard let character = visibleTextCharacterWithLocation(
            near: candidateOffset,
            preferPrevious: preferPrevious,
            pageStarts: pageStarts
        ) else { return nil }

        let lines = textLines(onPageAt: character.pageIndex, pageStarts: pageStarts)
        guard let lineIndex = lines.firstIndex(where: { line in
            line.characters.contains { $0.globalOffset == character.globalOffset }
        }) else { return nil }

        let line = lines[lineIndex]
        let useTrailingEdge = preferTrailingEdge || insertionOffset >= totalLength
        let slotIndex = slotIndex(
            forInsertionOffset: insertionOffset,
            preferTrailingEdge: useTrailingEdge,
            in: line
        )
        let slotPoint = pointForSlot(slotIndex, in: line)

        return VimTextCaret(
            offset: insertionOffset,
            pageIndex: character.pageIndex,
            slotIndex: slotIndex,
            point: NSPoint(
                x: slotPoint.x,
                y: slotPoint.y
            ),
            lineMidY: line.midY
        )
    }

    func visibleTextCharacterWithLocation(
        near offset: Int,
        preferPrevious: Bool,
        pageStarts: [Int]
    ) -> (pageIndex: Int, globalOffset: Int, bounds: NSRect)? {
        guard let totalLength = pageStarts.last, totalLength > 0 else { return nil }

        let clampedOffset = min(max(offset, 0), totalLength - 1)
        if preferPrevious {
            if let previous = visibleTextCharacterWithLocation(
                in: stride(from: clampedOffset, through: 0, by: -1),
                pageStarts: pageStarts
            ) {
                return previous
            }
            return visibleTextCharacterWithLocation(
                in: stride(from: clampedOffset + 1, to: totalLength, by: 1),
                pageStarts: pageStarts
            )
        }

        if let next = visibleTextCharacterWithLocation(
            in: stride(from: clampedOffset, to: totalLength, by: 1),
            pageStarts: pageStarts
        ) {
            return next
        }
        return visibleTextCharacterWithLocation(
            in: stride(from: clampedOffset - 1, through: 0, by: -1),
            pageStarts: pageStarts
        )
    }

    func visibleTextCharacterWithLocation<S: Sequence>(
        in offsets: S,
        pageStarts: [Int]
    ) -> (pageIndex: Int, globalOffset: Int, bounds: NSRect)? where S.Element == Int {
        for offset in offsets {
            guard let pageIndex = pageIndex(containing: offset, pageStarts: pageStarts),
                  let page = document?.page(at: pageIndex) else { continue }

            let characterIndex = offset - pageStarts[pageIndex]
            guard characterIndex >= 0, characterIndex < page.numberOfCharacters else { continue }
            guard !isNewlineCharacter(at: characterIndex, in: page.string as NSString?) else { continue }

            let bounds = page.characterBounds(at: characterIndex)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            return (pageIndex, offset, bounds)
        }

        return nil
    }

    func scrollTextCaretToVisible(_ caret: VimTextCaret) {
        guard let document,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView,
              let page = document.page(at: caret.pageIndex) else { return }

        guard let endpointRectInView = viewRect(
            for: NSRect(x: caret.point.x - 2, y: caret.point.y - 8, width: 4, height: 16),
            on: page
        ) else { return }

        scrollRectToComfortableTextArea(endpointRectInView, scrollView: scrollView, documentView: documentView)
    }

    func scrollTextSelectionEndpointToVisible(
        anchorOffset: Int,
        extentOffset: Int,
        pageStarts: [Int]
    ) {
        guard let document,
              let totalLength = pageStarts.last,
              totalLength > 0,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView else { return }

        let activeOffset = activeCharacterOffset(
            extentOffset: extentOffset,
            anchorOffset: anchorOffset,
            totalLength: totalLength
        )
        guard let pageIndex = pageIndex(containing: activeOffset, pageStarts: pageStarts),
              let page = document.page(at: pageIndex) else { return }

        let localOffset = activeOffset - pageStarts[pageIndex]
        guard localOffset >= 0, localOffset < page.numberOfCharacters else { return }

        let characterBounds = page.characterBounds(at: localOffset).insetBy(dx: -8, dy: -10)
        guard characterBounds.width > 0, characterBounds.height > 0,
              let endpointRectInView = viewRect(for: characterBounds, on: page) else { return }

        scrollRectToComfortableTextArea(endpointRectInView, scrollView: scrollView, documentView: documentView)
    }

    func scrollRectToComfortableTextArea(
        _ endpointRectInView: NSRect,
        scrollView: NSScrollView,
        documentView: NSView
    ) {
        let endpointRect = convert(endpointRectInView, to: documentView)
        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds
        let marginX = min(44, visibleRect.width * 0.12)
        let marginY = min(56, visibleRect.height * 0.14)
        let comfortableRect = visibleRect.insetBy(dx: marginX, dy: marginY)

        guard !comfortableRect.contains(endpointRect) else { return }

        let documentBounds = documentView.bounds
        let maxOriginX = max(documentBounds.minX, documentBounds.maxX - visibleRect.width)
        let maxOriginY = max(documentBounds.minY, documentBounds.maxY - visibleRect.height)
        var nextOrigin = visibleRect.origin

        if endpointRect.minX < comfortableRect.minX {
            nextOrigin.x += endpointRect.minX - comfortableRect.minX
        } else if endpointRect.maxX > comfortableRect.maxX {
            nextOrigin.x += endpointRect.maxX - comfortableRect.maxX
        }

        if endpointRect.minY < comfortableRect.minY {
            nextOrigin.y += endpointRect.minY - comfortableRect.minY
        } else if endpointRect.maxY > comfortableRect.maxY {
            nextOrigin.y += endpointRect.maxY - comfortableRect.maxY
        }

        nextOrigin.x = min(max(documentBounds.minX, nextOrigin.x), maxOriginX)
        nextOrigin.y = min(max(documentBounds.minY, nextOrigin.y), maxOriginY)

        guard abs(nextOrigin.x - visibleRect.origin.x) > 0.5
            || abs(nextOrigin.y - visibleRect.origin.y) > 0.5 else { return }

        clipView.scroll(to: nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func textPageStarts(in document: PDFDocument) -> [Int] {
        var starts: [Int] = []
        var offset = 0

        for pageIndex in 0..<document.pageCount {
            starts.append(offset)
            offset += document.page(at: pageIndex)?.numberOfCharacters ?? 0
        }

        starts.append(offset)
        return starts
    }

    func wordForwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length)

        if index < length, characterClass(at: index, in: text) != .whitespace {
            let currentClass = characterClass(at: index, in: text)
            while index < length, characterClass(at: index, in: text) == currentClass {
                index += 1
            }
        }

        while index < length, characterClass(at: index, in: text) == .whitespace {
            index += 1
        }

        return index
    }

    func wordBackwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length) - 1

        while index > 0, characterClass(at: index, in: text) == .whitespace {
            index -= 1
        }

        guard index >= 0 else { return 0 }
        let targetClass = characterClass(at: index, in: text)
        while index > 0, characterClass(at: index - 1, in: text) == targetClass {
            index -= 1
        }

        return index
    }

    func wordEndOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length)

        while index < length, characterClass(at: index, in: text) == .whitespace {
            index += 1
        }

        guard index < length else { return length }
        let targetClass = characterClass(at: index, in: text)
        while index + 1 < length, characterClass(at: index + 1, in: text) == targetClass {
            index += 1
        }

        return min(length, index + 1)
    }

    func documentText(in document: PDFDocument) -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()
    }

    func characterClass(at offset: Int, in text: NSString) -> VimTextCharacterClass {
        guard offset >= 0, offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return .punctuation
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return .whitespace
        }

        if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
            return .word
        }

        return .punctuation
    }

    func isNewlineCharacter(at offset: Int, in text: NSString?) -> Bool {
        guard let text,
              offset >= 0,
              offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return false
        }

        return CharacterSet.newlines.contains(scalar)
    }

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

@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
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
}

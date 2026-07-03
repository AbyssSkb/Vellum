import Foundation
import PDFKit

enum AIExplanationContextBuilder {
    static func context(
        for selection: PDFSelection,
        selectedText: String,
        document: PDFDocument?
    ) -> AIExplanationContext? {
        guard let document else { return nil }
        let normalizedSelectedText = AISelectedTextNormalizer.normalized(selectedText)
        guard !normalizedSelectedText.isEmpty else { return nil }

        let pages = selection.pages
        let pageNumbers = pages.compactMap { page -> Int? in
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index + 1
        }
        let pageText = pages
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: "\n\n")
        let paragraphContext = paragraphContext(
            selectedText: normalizedSelectedText,
            in: pageText
        )
        let anchoredContext = anchoredContext(
            for: selection,
            selectedText: normalizedSelectedText,
            document: document
        )
        let url = document.documentURL

        return AIExplanationContext(
            selectedText: normalizedSelectedText,
            previousParagraph: paragraphContext.previous,
            currentParagraph: paragraphContext.current,
            nextParagraph: paragraphContext.next,
            nearbyText: paragraphContext.nearby,
            fileName: url?.lastPathComponent ?? "Untitled PDF",
            documentKey: url?.standardizedFileURL.path,
            directoryName: url?.deletingLastPathComponent().lastPathComponent,
            outlineTitle: document.outlineItem(for: selection)?.label?.nilIfEmpty,
            pageNumbers: pageNumbers.isEmpty ? [1] : pageNumbers,
            anchoredContext: anchoredContext
        )
    }

    private static func anchoredContext(
        for selection: PDFSelection,
        selectedText: String,
        document: PDFDocument
    ) -> String? {
        let lineSelections = selection.selectionsByLine()
        let pages = selection.pages
        guard !pages.isEmpty else { return nil }

        let sections = pages.compactMap { page -> String? in
            let pageIndex = document.index(for: page)
            let pageNumber = pageIndex == NSNotFound ? nil : pageIndex + 1
            let pageBounds = page.bounds(for: .cropBox)
            let selectedLines = lineSelections.filter { lineSelection in
                lineSelection.pages.contains { $0 === page }
            }
            let bounds = selectedBounds(for: selectedLines, fallbackSelection: selection, page: page)
            guard !bounds.isEmpty else { return nil }

            let before = contextText(
                on: page,
                in: contextRectAbove(bounds, pageBounds: pageBounds)
            )
            let after = contextText(
                on: page,
                in: contextRectBelow(bounds, pageBounds: pageBounds)
            )
            let selectedBlock = anchoredSelectedBlock(
                selectedLines: selectedLines,
                selectedText: selectedText,
                page: page,
                pageBounds: pageBounds
            )

            let label = pageNumber.map { "Page \($0):" } ?? "Page:"
            let body = [
                before,
                selectedBlock,
                after
            ]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: "\n")
            .limitedForAIContext(2200)

            guard !body.isEmpty else { return nil }
            return "\(label)\n\(body)"
        }

        return sections
            .joined(separator: "\n\n")
            .limitedForAIContext(5200)
            .nilIfEmpty
    }

    private static func selectedBounds(
        for lineSelections: [PDFSelection],
        fallbackSelection: PDFSelection,
        page: PDFPage
    ) -> NSRect {
        let lineBounds = lineSelections
            .map { $0.bounds(for: page) }
            .filter { !$0.isEmpty }
        if let first = lineBounds.first {
            return lineBounds.dropFirst().reduce(first) { $0.union($1) }
        }

        return fallbackSelection.bounds(for: page)
    }

    private static func anchoredSelectedBlock(
        selectedLines: [PDFSelection],
        selectedText: String,
        page: PDFPage,
        pageBounds: NSRect
    ) -> String? {
        let selectedLineTexts = selectedLines.compactMap { lineSelection in
            lineSelection.string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        if selectedLineTexts.count > 1 {
            let normalizedSelection = AISelectedTextNormalizer
                .normalized(selectedLineTexts.joined(separator: "\n"))
                .nilIfEmpty
            if let normalizedSelection {
                return "<selected>\(normalizedSelection)</selected>"
            }
        }

        let lineBlocks = selectedLines.compactMap { lineSelection -> String? in
            guard let selectedLineText = lineSelection.string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else { return nil }
            let normalizedSelectedLineText = AISelectedTextNormalizer.normalized(selectedLineText)

            let lineBounds = lineSelection.bounds(for: page)
            let lineContext = contextText(
                on: page,
                in: expandedLineRect(for: lineBounds, pageBounds: pageBounds)
            ) ?? normalizedSelectedLineText

            return markSelectedText(
                normalizedSelectedLineText,
                in: lineContext,
                selectedBounds: lineBounds,
                pageBounds: pageBounds
            )
        }

        if !lineBlocks.isEmpty {
            return lineBlocks.joined(separator: "\n")
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "<selected>\(trimmed)</selected>"
    }

    private static func markSelectedText(
        _ selectedText: String,
        in contextText: String,
        selectedBounds: NSRect,
        pageBounds: NSRect
    ) -> String {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty, !trimmedContext.isEmpty else {
            return "<selected>\(trimmedSelection)</selected>"
        }

        let ranges = ranges(of: trimmedSelection, in: trimmedContext)
        guard let range = chosenRange(
            from: ranges,
            in: trimmedContext,
            selectedBounds: selectedBounds,
            pageBounds: pageBounds
        ) else {
            return "\(trimmedContext)\n<selected>\(trimmedSelection)</selected>"
        }

        var marked = trimmedContext
        marked.insert(contentsOf: "</selected>", at: range.upperBound)
        marked.insert(contentsOf: "<selected>", at: range.lowerBound)
        return marked
    }

    private static func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func chosenRange(
        from ranges: [Range<String.Index>],
        in text: String,
        selectedBounds: NSRect,
        pageBounds: NSRect
    ) -> Range<String.Index>? {
        guard ranges.count > 1, pageBounds.width > 0 else {
            return ranges.first
        }

        let selectedFraction = max(
            0,
            min(1, (selectedBounds.midX - pageBounds.minX) / pageBounds.width)
        )
        let textLength = max(1, text.utf16.count)

        return ranges.min { lhs, rhs in
            distance(lhs) < distance(rhs)
        }

        func distance(_ range: Range<String.Index>) -> CGFloat {
            let nsRange = NSRange(range, in: text)
            let rangeFraction = (CGFloat(nsRange.location) + CGFloat(nsRange.length) / 2) / CGFloat(textLength)
            return abs(rangeFraction - selectedFraction)
        }
    }

    private static func contextText(on page: PDFPage, in rect: NSRect?) -> String? {
        guard let rect, !rect.isEmpty else { return nil }
        guard let text = page.selection(for: rect)?.string else { return nil }
        return AISelectedTextNormalizer.normalized(text).nilIfEmpty
    }

    private static func expandedLineRect(for lineBounds: NSRect, pageBounds: NSRect) -> NSRect {
        guard !lineBounds.isEmpty else { return .zero }

        let verticalPadding: CGFloat = 2
        return NSRect(
            x: pageBounds.minX,
            y: max(pageBounds.minY, lineBounds.minY - verticalPadding),
            width: pageBounds.width,
            height: min(
                pageBounds.maxY,
                lineBounds.maxY + verticalPadding
            ) - max(pageBounds.minY, lineBounds.minY - verticalPadding)
        )
    }

    private static func contextRectAbove(_ selectedBounds: NSRect, pageBounds: NSRect) -> NSRect? {
        contextRect(
            x: pageBounds.minX,
            y: selectedBounds.maxY + 3,
            width: pageBounds.width,
            height: min(360, pageBounds.maxY - selectedBounds.maxY - 3)
        )
    }

    private static func contextRectBelow(_ selectedBounds: NSRect, pageBounds: NSRect) -> NSRect? {
        contextRect(
            x: pageBounds.minX,
            y: max(pageBounds.minY, selectedBounds.minY - 363),
            width: pageBounds.width,
            height: min(360, selectedBounds.minY - pageBounds.minY - 3)
        )
    }

    private static func contextRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect? {
        guard width > 0, height > 1 else { return nil }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func paragraphContext(
        selectedText: String,
        in text: String
    ) -> (previous: String?, current: String?, next: String?, nearby: String) {
        let paragraphs = paragraphs(from: text)
        let selectedNeedle = selectedText.normalizedForAIContext.prefixString(240)

        if let index = paragraphs.firstIndex(where: { paragraph in
            let normalized = paragraph.normalizedForAIContext
            return normalized.contains(selectedNeedle)
                || selectedNeedle.contains(normalized.prefixString(240))
        }) {
            let previous = index > 0 ? paragraphs[index - 1] : nil
            let current = paragraphs[index]
            let next = index + 1 < paragraphs.count ? paragraphs[index + 1] : nil
            let nearby = [previous, current, next]
                .compactMap { $0 }
                .joined(separator: "\n\n")
                .limitedForAIContext()
            return (previous, current, next, nearby)
        }

        return (
            nil,
            nil,
            nil,
            text.trimmingCharacters(in: .whitespacesAndNewlines).limitedForAIContext()
        )
    }

    private static func paragraphs(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [String] = []
        var currentLines: [String] = []

        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !currentLines.isEmpty {
                    paragraphs.append(currentLines.joined(separator: " "))
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(trimmed)
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(currentLines.joined(separator: " "))
        }

        if paragraphs.count > 1 {
            return paragraphs.map { $0.limitedForAIContext(1600) }
        }

        return normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .chunked(maxCharacters: 900)
            .map { $0.limitedForAIContext(1600) }
    }
}

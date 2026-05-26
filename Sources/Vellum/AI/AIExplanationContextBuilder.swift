import Foundation
import PDFKit

enum AIExplanationContextBuilder {
    static func context(
        for selection: PDFSelection,
        selectedText: String,
        document: PDFDocument?
    ) -> AIExplanationContext? {
        guard let document else { return nil }

        let pages = selection.pages
        let pageNumbers = pages.compactMap { page -> Int? in
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index + 1
        }
        let pageText = pages
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: "\n\n")
        let paragraphContext = paragraphContext(
            selectedText: selectedText,
            in: pageText
        )
        let url = document.documentURL

        return AIExplanationContext(
            selectedText: selectedText,
            previousParagraph: paragraphContext.previous,
            currentParagraph: paragraphContext.current,
            nextParagraph: paragraphContext.next,
            nearbyText: paragraphContext.nearby,
            fileName: url?.lastPathComponent ?? "Untitled PDF",
            directoryName: url?.deletingLastPathComponent().lastPathComponent,
            outlineTitle: document.outlineItem(for: selection)?.label?.nilIfEmpty,
            pageNumbers: pageNumbers.isEmpty ? [1] : pageNumbers
        )
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

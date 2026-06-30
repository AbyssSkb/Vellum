import Foundation

enum AIExplanationPronunciationSpeech {
    static func normalizedSelectionText(_ text: String?) -> String? {
        guard let text else { return nil }

        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        return normalized.count > 120 ? String(normalized.prefix(120)) : normalized
    }

    static func speechText(selectedText: String?, markdown: String) -> String? {
        if let selectedText = normalizedSelectionText(selectedText) {
            return selectedText
        }

        return pronunciationFallbackText(from: markdown)
    }

    static func isPronunciationHeading(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":："))
            .lowercased()

        return normalized == "音标"
            || normalized == "pronunciation"
            || normalized == "reading"
    }

    private static func pronunciationFallbackText(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { rawLine in
            guard let heading = markdownHeadingText(rawLine) else { return false }
            return isPronunciationHeading(heading)
        }) else {
            return nil
        }

        for rawLine in lines.dropFirst(headingIndex + 1) {
            if markdownHeadingText(rawLine) != nil {
                return nil
            }

            let candidate = rawLine
                .replacingOccurrences(of: #"^[\s>*-]+|\*\*|__|`"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let candidate = normalizedSelectionText(candidate),
               !looksLikeOnlyPhoneticSymbols(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func markdownHeadingText(_ rawLine: String) -> String? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let markerEnd = trimmed.firstIndex(where: { $0 != "#" }),
              trimmed[..<markerEnd].count <= 6,
              trimmed[markerEnd].isWhitespace else {
            return nil
        }

        return trimmed[markerEnd...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeOnlyPhoneticSymbols(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("/") && trimmed.hasSuffix("/"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            || trimmed.contains("/") {
            return true
        }

        let stripped = text
            .replacingOccurrences(of: #"[\/\[\]\(\)ˈˌ.:;·\s]+"#, with: "", options: .regularExpression)
        guard !stripped.isEmpty else { return true }

        return !stripped.contains { character in
            character.isLetter && character.isASCII
        }
    }
}

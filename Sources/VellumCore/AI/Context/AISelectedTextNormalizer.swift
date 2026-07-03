import Foundation

enum AISelectedTextNormalizer {
    static func normalized(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var paragraphs: [[String]] = []
        var currentLines: [String] = []

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = collapsedHorizontalWhitespace(
                rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            if line.isEmpty {
                if !currentLines.isEmpty {
                    paragraphs.append(currentLines)
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(currentLines)
        }

        return paragraphs
            .map(normalizedParagraph)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func normalizedParagraph(lines: [String]) -> String {
        var paragraph = ""

        for line in lines {
            if paragraph.isEmpty {
                paragraph = line
            } else if shouldJoinAfterLineEndingHyphen(paragraph, nextLine: line) {
                paragraph.removeLast()
                paragraph += line
            } else if shouldJoinWithoutSpace(paragraph, nextLine: line) {
                paragraph += line
            } else {
                paragraph += " " + line
            }
        }

        return paragraph
    }

    private static func collapsedHorizontalWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func shouldJoinAfterLineEndingHyphen(_ paragraph: String, nextLine: String) -> Bool {
        guard let last = paragraph.last,
              isLineEndingHyphen(last),
              let previous = paragraph.dropLast().last,
              let first = nextLine.first else {
            return false
        }

        return previous.isLetter && first.isLetter
    }

    private static func shouldJoinWithoutSpace(_ paragraph: String, nextLine: String) -> Bool {
        guard let last = paragraph.last,
              let first = nextLine.first else {
            return false
        }

        return (isCJK(last) && isCJK(first)) || isClosingPunctuation(first)
    }

    private static func isLineEndingHyphen(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x002D, 0x00AD, 0x2010, 0x2011:
                return true
            default:
                return false
            }
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x3040...0x30FF,
                 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private static func isClosingPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x002C, 0x002E, 0x003A, 0x003B, 0x003F, 0x0021,
                 0x0025, 0x0029, 0x005D, 0x007D:
                return true
            default:
                return false
            }
        }
    }
}

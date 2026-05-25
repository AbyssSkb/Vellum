import Foundation

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedForAIContext: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    var aiPopoverTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.count > 44 ? String(trimmed.prefix(44)) + "..." : trimmed
        return "Explain: \(title)"
    }

    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }

    func limitedForAIContext(_ maxLength: Int = 4000) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "\n..."
    }
}

extension Array where Element == String {
    func chunked(maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        for line in self {
            if current.count + line.count + 1 > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = line
            } else if current.isEmpty {
                current = line
            } else {
                current += " " + line
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}

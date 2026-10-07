import Foundation

public struct UpdateVersion: Comparable, Equatable {
    public let components: [Int]

    public init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed

        self.components = normalized
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }

    public static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

public struct AppReleaseNotesSection: Equatable {
    public let version: String?
    public let notes: [String]

    public init(version: String?, notes: [String]) {
        self.version = version
        self.notes = notes
    }
}

public enum AppReleaseNotesParser {
    public static func sections(
        from releaseNotes: String?,
        maxPlainNotes: Int = 8,
        maxNotesPerVersion: Int = 8
    ) -> [AppReleaseNotesSection] {
        guard let releaseNotes else { return [] }

        var plainNotes: [String] = []
        var sections: [AppReleaseNotesSection] = []
        var currentVersion: String?
        var currentNotes: [String] = []

        func appendCurrentSectionIfNeeded() {
            guard let currentVersion, !currentNotes.isEmpty else { return }
            sections.append(AppReleaseNotesSection(
                version: currentVersion,
                notes: Array(currentNotes.prefix(maxNotesPerVersion))
            ))
            currentNotes.removeAll()
        }

        for rawLine in releaseNotes.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if let version = versionHeading(from: line) {
                appendCurrentSectionIfNeeded()
                currentVersion = version
                continue
            }

            guard let note = cleanReleaseNoteLine(line) else { continue }
            if currentVersion != nil {
                currentNotes.append(note)
            } else if sections.isEmpty {
                plainNotes.append(note)
            }
        }

        appendCurrentSectionIfNeeded()

        if !sections.isEmpty {
            return sections
        }

        guard !plainNotes.isEmpty else { return [] }
        return [AppReleaseNotesSection(version: nil, notes: Array(plainNotes.prefix(maxPlainNotes)))]
    }

    private static func versionHeading(from line: String) -> String? {
        var heading = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard heading.hasPrefix("#") else { return nil }

        while heading.hasPrefix("#") {
            heading = String(heading.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        heading = heading
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = heading.first else { return nil }
        if first == "v" || first == "V" {
            let remaining = heading.dropFirst()
            return remaining.first?.isNumber == true ? heading : nil
        }

        return first.isNumber ? heading : nil
    }

    private static func cleanReleaseNoteLine(_ rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let lowercasedLine = line.lowercased()
        guard !lowercasedLine.hasPrefix("what's changed"),
              !lowercasedLine.hasPrefix("full changelog") else {
            return nil
        }

        if line.hasPrefix("#") {
            return nil
        }

        line = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if line.lowercased().hasPrefix("full changelog") {
            return nil
        }

        while line.hasPrefix("-") || line.hasPrefix("*") {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if line.lowercased().hasPrefix("full changelog") {
            return nil
        }

        guard !line.isEmpty else { return nil }
        return line
    }
}

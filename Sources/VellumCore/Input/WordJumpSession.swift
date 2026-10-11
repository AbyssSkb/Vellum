struct WordJumpSession {
    struct Match: Equatable {
        let wordIndex: Int
        let label: String
    }

    enum Action: Equatable {
        case updated
        case selected(Int)
        case cancelled
    }

    private let words: [String]
    private(set) var query = ""
    private(set) var labelPrefix = ""
    private(set) var matches: [Match] = []

    var displayedMatches: [Match] {
        matches.filter { labelPrefix.isEmpty || $0.label.hasPrefix(labelPrefix) }
    }

    init(words: [String]) {
        self.words = words.map { $0.lowercased() }
    }

    mutating func input(_ key: String) -> Action {
        switch key {
        case "\u{1b}":
            return .cancelled
        case "\u{7f}", "\u{8}":
            if !labelPrefix.isEmpty {
                labelPrefix.removeLast()
            } else if !query.isEmpty {
                query.removeLast()
                updateMatches()
            }
            return .updated
        case "\r", "\n":
            return displayedMatches.first.map { .selected($0.wordIndex) } ?? .updated
        default:
            guard !key.isEmpty else { return .updated }
        }

        let proposedLabel = labelPrefix + key.lowercased()
        if key.count == 1, matches.contains(where: { !$0.label.isEmpty && $0.label.hasPrefix(proposedLabel) }) {
            labelPrefix = proposedLabel
            if let match = matches.first(where: { $0.label == proposedLabel }) {
                return .selected(match.wordIndex)
            }
            return .updated
        }

        labelPrefix = ""
        query += key
        updateMatches()
        return .updated
    }

    private mutating func updateMatches() {
        guard !query.isEmpty else {
            matches = []
            return
        }

        let prefix = query.lowercased()
        let indices = words.indices.filter { words[$0].hasPrefix(prefix) }
        let continuations = Set(indices.compactMap { words[$0].dropFirst(prefix.count).first })
        let alphabet = Array("asdfghjklqwertyuiopzxcvbnm").filter { !continuations.contains($0) }
        guard !alphabet.isEmpty, alphabet.count > 1 || indices.count <= 1 else {
            matches = indices.map { Match(wordIndex: $0, label: "") }
            return
        }

        var length = 1
        var capacity = alphabet.count
        while capacity < indices.count {
            capacity *= alphabet.count
            length += 1
        }

        let allowed = Set(alphabet)
        let previous = matches.filter { !$0.label.isEmpty && $0.label.allSatisfy(allowed.contains) }
        // Keep surviving labels the same length when narrowing a large set of matches.
        length = max(length, previous.first?.label.count ?? 1)
        let retained = Dictionary(uniqueKeysWithValues: previous.filter {
            $0.label.count == length && indices.contains($0.wordIndex)
        }.map { ($0.wordIndex, $0.label) })
        var used = Set(retained.values)
        var ordinal = 0
        matches = indices.map { index in
            if let label = retained[index] { return Match(wordIndex: index, label: label) }
            var label: String
            repeat {
                var value = ordinal
                var characters: [Character] = []
                for _ in 0..<length {
                    characters.append(alphabet[value % alphabet.count])
                    value /= alphabet.count
                }
                label = String(characters.reversed())
                ordinal += 1
            } while used.contains(label)
            used.insert(label)
            return Match(wordIndex: index, label: label)
        }
    }
}

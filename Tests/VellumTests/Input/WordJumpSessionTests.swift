import Testing
@testable import VellumCore

@Suite("Word jump session")
struct WordJumpSessionTests {
    @Test
    func duplicateWordsKeepDistinctOriginalIndices() {
        var session = WordJumpSession(words: ["other", "delta", "delta", "DELTA"])
        #expect(session.matches.isEmpty)
        #expect(session.input("d") == .updated)
        #expect(session.matches.map(\.wordIndex) == [1, 2, 3])
        #expect(Set(session.matches.map(\.label)).count == 3)
        let label = session.matches[2].label
        #expect(session.input(label) == .selected(3))
    }

    @Test
    func prefixMatchesIgnoreCaseAndDoNotMatchInsideAWord() {
        var session = WordJumpSession(words: ["Alpha", "ALPINE", "scalp", "beta"])
        #expect(session.input("A") == .updated)
        #expect(session.input("l") == .updated)
        #expect(session.input("P") == .updated)
        #expect(session.query == "AlP")
        #expect(session.matches.map(\.wordIndex) == [0, 1])
    }

    @Test
    func labelsNeverConsumePossiblePrefixContinuations() {
        var session = WordJumpSession(words: ["start", "stop", "shape"])
        _ = session.input("s")
        #expect(session.matches.allSatisfy { !$0.label.contains("t") && !$0.label.contains("h") })
        #expect(session.input("t") == .updated)
        #expect(session.query == "st")
        #expect(session.matches.map(\.wordIndex) == [0, 1])
        #expect(session.matches.allSatisfy { !$0.label.contains("a") && !$0.label.contains("o") })
    }

    @Test
    func everyTargetInALargeSetHasAnUnambiguousReachableLabel() {
        var session = WordJumpSession(words: Array(repeating: "word", count: 80))
        _ = session.input("w")
        #expect(Set(session.matches.map(\.label)).count == 80)
        #expect(session.matches.allSatisfy { $0.label.count == 2 })
        for match in session.matches {
            var candidate = session
            let keys = Array(match.label)
            #expect(candidate.input(String(keys[0])) == .updated)
            #expect(candidate.displayedMatches.allSatisfy { $0.label.hasPrefix(String(keys[0])) })
            #expect(candidate.input(String(keys[1])) == .selected(match.wordIndex))
        }
    }

    @Test
    func backspaceRemovesTheLabelPrefixBeforeTheQuery() {
        var session = WordJumpSession(words: Array(repeating: "word", count: 80))
        _ = session.input("w")
        let firstLabel = session.matches[0].label
        _ = session.input(String(firstLabel.first!))
        #expect(!session.labelPrefix.isEmpty)
        #expect(session.input("\u{7f}") == .updated)
        #expect(session.labelPrefix.isEmpty)
        #expect(session.query == "w")
        #expect(session.displayedMatches.count == 80)
        #expect(session.input("\u{8}") == .updated)
        #expect(session.query.isEmpty)
        #expect(session.matches.isEmpty)
        #expect(session.input("\u{7f}") == .updated)
    }

    @Test
    func noResultsCanBeEditedAndEscapeCancels() {
        var session = WordJumpSession(words: ["alpha"])
        #expect(session.input("9") == .updated)
        #expect(session.input("!") == .updated)
        #expect(session.matches.isEmpty)
        #expect(session.input("\r") == .updated)
        _ = session.input("\u{7f}")
        _ = session.input("\u{7f}")
        #expect(session.input("al") == .updated)
        #expect(session.matches.map(\.wordIndex) == [0])
        #expect(session.input("\u{1b}") == .cancelled)
    }

    @Test
    func returnSelectsTheFirstFilteredMatchWithoutAutomaticallySelectingUniqueMatches() {
        var session = WordJumpSession(words: Array(repeating: "word", count: 80))
        #expect(session.input("\r") == .updated)
        #expect(session.input("word") == .updated)
        let prefix = String(session.matches[30].label.first!)
        _ = session.input(prefix.uppercased())
        let expected = session.displayedMatches[0].wordIndex
        #expect(session.input("\n") == .selected(expected))
        var unique = WordJumpSession(words: ["alpha"])
        #expect(unique.input("alpha") == .updated)
        #expect(unique.input("\r") == .selected(0))
    }

    @Test
    func oneAvailableLetterWaitsForMorePrefixInputWhenItCannotLabelEveryMatch() {
        let continuations = "sdfghjklqwertyuiopzxcvbnm"
        var session = WordJumpSession(words: continuations.map { "p\($0)word" })
        _ = session.input("p")
        #expect(session.matches.count == 25)
        #expect(session.matches.allSatisfy { $0.label.isEmpty })
        #expect(session.input("\r") == .selected(0))
        #expect(session.input("s") == .updated)
        #expect(session.query == "ps")
        #expect(session.matches.count == 1)
        #expect(!session.matches[0].label.isEmpty)
    }

    @Test
    func survivingLegalLabelsAreReusedIncludingTheirLength() {
        var session = WordJumpSession(words: ["alpha", "apple", "beta"])
        _ = session.input("a")
        let original = session.matches[0].label
        _ = session.input("l")
        #expect(session.matches == [.init(wordIndex: 0, label: original)])

        var large = WordJumpSession(words: (0..<80).map { "word\($0)" })
        _ = large.input("w")
        let labels = Dictionary(uniqueKeysWithValues: large.matches.map { ($0.wordIndex, $0.label) })
        _ = large.input("ord1")
        #expect(large.query == "word1")
        #expect(large.matches.count == 11)
        #expect(large.matches.allSatisfy { $0.label == labels[$0.wordIndex] && $0.label.count == 2 })
    }
}

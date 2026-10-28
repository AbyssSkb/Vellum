@preconcurrency import AppKit
import Testing
@testable import VellumCore

@Suite("Word jump label geometry")
struct WordJumpLabelGeometryTests {
    @Test
    func shortWordsRevealRemainingLabelLettersWithinTheirOwnCharacterSlots() {
        #expect(WordJumpLabelGeometry.visibleLabel("ad", typedPrefix: "", characterCount: 1) == "a")
        #expect(WordJumpLabelGeometry.visibleLabel("ad", typedPrefix: "a", characterCount: 1) == "d")
        #expect(WordJumpLabelGeometry.visibleLabel("ad", typedPrefix: "a", characterCount: 2) == "ad")
        #expect(WordJumpLabelGeometry.visibleLabel("abc", typedPrefix: "a", characterCount: 2) == "bc")
    }

    @Test
    func labelsCoverTheBeginningOfTheirWord() {
        let word = NSRect(x: 80, y: 70, width: 60, height: 18)
        let frame = WordJumpLabelGeometry.frame(
            for: word, labelSize: NSSize(width: 22, height: 17),
            in: NSRect(x: 0, y: 0, width: 240, height: 160), avoiding: []
        )

        #expect(frame.minX == word.minX)
        #expect(frame.midY == word.midY)
        #expect(frame.intersects(word))
    }

    @Test
    func fontSizeFollowsWordHeightContinuouslyWithinReadableLimits() {
        func size(_ width: CGFloat, _ height: CGFloat) -> CGFloat {
            WordJumpLabelGeometry.fontSize(for: NSRect(x: 0, y: 0, width: width, height: height))
        }

        #expect(size(80, 4) == 11)
        #expect(size(80, 18) > size(80, 4))
        #expect(size(80, 18.1) > size(80, 18))
        #expect(size(80, 18.1) - size(80, 18) < 0.2)
        #expect(size(80, 19) > size(80, 18.1))
        #expect(size(80, 100) == 14)
        #expect(size(4, 20) == size(80, 20))
        #expect(WordJumpLabelGeometry.fontSize(for: NSRect(x: 0, y: 0, width: 18, height: 80), rotation: 90) == size(80, 18))
        #expect(WordJumpLabelGeometry.fontSize(for: NSRect(x: 0, y: 0, width: 18, height: 4), rotation: 270) == size(80, 18))
    }

    @Test
    func labelsAtViewportEdgesStillCoverTheirVisibleWord() {
        let viewport = NSRect(x: 10, y: 20, width: 240, height: 140)
        let words = [
            NSRect(x: 218, y: 23, width: 28, height: 16),
            NSRect(x: 8, y: 70, width: 16, height: 18),
            NSRect(x: 80, y: 148, width: 32, height: 20),
            NSRect(x: 80, y: 8, width: 32, height: 20)
        ]
        for word in words {
            let frame = WordJumpLabelGeometry.frame(
                for: word, labelSize: NSSize(width: 32, height: 20),
                in: viewport, avoiding: []
            )
            #expect(viewport.insetBy(dx: 2, dy: 2).contains(frame))
            #expect(frame.size == NSSize(width: 32, height: 20))
            #expect(frame.intersects(word.intersection(viewport)))
        }
    }

    @Test
    func denseShortWordsKeepTheirLabelsAnchoredToTheirOwnWord() {
        let viewport = NSRect(x: 0, y: 0, width: 260, height: 160)
        var occupied: [NSRect] = []
        for x in stride(from: CGFloat(80), through: 128, by: 12) {
            let word = NSRect(x: x, y: 70, width: 9, height: 18)
            let frame = WordJumpLabelGeometry.frame(
                for: word, labelSize: NSSize(width: 22, height: 17),
                in: viewport, avoiding: occupied
            )
            #expect(viewport.insetBy(dx: 2, dy: 2).contains(frame))
            #expect(frame.minX == word.minX)
            #expect(frame.intersection(word).height >= 2)
            #expect(occupied.allSatisfy { !$0.intersects(frame) || $0.intersection(frame).height <= 2 })
            occupied.append(frame)
        }
    }

    @Test
    func occupiedWordStartOnlyCausesASmallDeterministicCrossAxisOffset() {
        let word = NSRect(x: 80, y: 70, width: 40, height: 16)
        let labelSize = NSSize(width: 32, height: 20)
        let viewport = NSRect(x: 0, y: 0, width: 240, height: 160)
        let occupied = [NSRect(x: 80, y: 68, width: 32, height: 20)]
        let first = WordJumpLabelGeometry.frame(
            for: word, labelSize: labelSize, in: viewport, avoiding: occupied
        )
        let repeated = WordJumpLabelGeometry.frame(
            for: word, labelSize: labelSize, in: viewport, avoiding: occupied
        )

        #expect(first == repeated)
        #expect(first.minX == word.minX)
        #expect(first.intersection(word).height >= 2)
        #expect(first.intersection(occupied[0]).height <= 4)
        #expect(viewport.insetBy(dx: 2, dy: 2).contains(first))
    }

    @Test
    func rotatedWordsUseTheirDisplayedStartingEdge() {
        let viewport = NSRect(x: 0, y: 0, width: 240, height: 240)
        let horizontal = NSRect(x: 80, y: 70, width: 60, height: 18)
        let vertical = NSRect(x: 80, y: 70, width: 18, height: 60)
        let cases: [(Int, NSRect, NSPoint)] = [
            (0, horizontal, NSPoint(x: 80, y: 70.5)),
            (90, vertical, NSPoint(x: 78, y: 113)),
            (180, horizontal, NSPoint(x: 118, y: 70.5)),
            (270, vertical, NSPoint(x: 78, y: 70)),
            (-90, vertical, NSPoint(x: 78, y: 70)),
            (450, vertical, NSPoint(x: 78, y: 113))
        ]
        for (rotation, word, origin) in cases {
            let frame = WordJumpLabelGeometry.frame(
                for: word, labelSize: NSSize(width: 22, height: 17),
                in: viewport, avoiding: [], rotation: rotation
            )
            #expect(frame.origin == origin)
            #expect(frame.intersects(word))
        }
    }
}

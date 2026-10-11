@preconcurrency import AppKit
import Testing
@testable import VellumCore

@Suite("Word jump label geometry")
struct WordJumpLabelGeometryTests {
    @Test
    func fontSizeFollowsWordHeightContinuouslyWithinReadableLimits() {
        func size(_ width: CGFloat, _ height: CGFloat) -> CGFloat {
            WordJumpLabelGeometry.fontSize(for: NSRect(x: 0, y: 0, width: width, height: height))
        }

        #expect(size(80, 4) == 12)
        #expect(abs(size(80, 18) - 14.4) < 0.001)
        #expect(abs(size(80, 18.1) - size(80, 18) - 0.08) < 0.001)
        #expect(size(80, 20) == 16)
        #expect(size(80, 100) == 20)
        #expect(size(4, 20) == 16)
        #expect(WordJumpLabelGeometry.fontSize(for: NSRect(x: 0, y: 0, width: 18, height: 80), rotation: 90) == size(80, 18))
        #expect(WordJumpLabelGeometry.fontSize(for: NSRect(x: 0, y: 0, width: 18, height: 4), rotation: 270) == size(80, 18))
    }

    @Test
    func neighboringLabelsNearViewportEdgeRemainVisibleAndSeparate() {
        let viewport = NSRect(x: 10, y: 20, width: 240, height: 140)
        let words = [
            NSRect(x: 218, y: 23, width: 28, height: 16),
            NSRect(x: 226, y: 24, width: 20, height: 16),
            NSRect(x: 232, y: 24, width: 14, height: 16)
        ]
        var occupied: [NSRect] = []
        for word in words {
            let frame = WordJumpLabelGeometry.frame(
                for: word, labelSize: NSSize(width: 32, height: 20),
                in: viewport, avoiding: occupied
            )
            #expect(viewport.insetBy(dx: 2, dy: 2).contains(frame))
            #expect(frame.size == NSSize(width: 32, height: 20))
            #expect(occupied.allSatisfy { !$0.intersects(frame) })
            occupied.append(frame)
        }
    }

    @Test
    func denseAdjacentWordsUseNearbyFreeSpace() {
        let viewport = NSRect(x: 0, y: 0, width: 260, height: 160)
        let words = [
            NSRect(x: 80, y: 70, width: 28, height: 16),
            NSRect(x: 104, y: 70, width: 32, height: 16),
            NSRect(x: 132, y: 70, width: 30, height: 16),
            NSRect(x: 159, y: 70, width: 22, height: 16)
        ]
        var occupied: [NSRect] = []
        for word in words {
            let frame = WordJumpLabelGeometry.frame(
                for: word, labelSize: NSSize(width: 36, height: 20),
                in: viewport, avoiding: occupied
            )
            #expect(viewport.insetBy(dx: 2, dy: 2).contains(frame))
            #expect(occupied.allSatisfy { !$0.intersects(frame) })
            #expect(abs(frame.midY - word.midY) <= 50)
            occupied.append(frame)
        }
    }

    @Test
    func placementIsDeterministicWithOccupiedPreferredPosition() {
        let word = NSRect(x: 80, y: 70, width: 40, height: 16)
        let labelSize = NSSize(width: 32, height: 20)
        let viewport = NSRect(x: 0, y: 0, width: 240, height: 160)
        let occupied = [NSRect(x: 120, y: 65, width: 36, height: 26)]
        let first = WordJumpLabelGeometry.frame(
            for: word, labelSize: labelSize, in: viewport, avoiding: occupied
        )
        let repeated = WordJumpLabelGeometry.frame(
            for: word, labelSize: labelSize, in: viewport, avoiding: occupied
        )

        #expect(first == repeated)
        #expect(!occupied[0].intersects(first))
        #expect(viewport.insetBy(dx: 2, dy: 2).contains(first))
    }
}

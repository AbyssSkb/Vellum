import AppKit
import Testing
@testable import VellumCore

@Suite("AI explanation geometry")
struct AIExplanationGeometryTests {
    @Test
    func groupBoundsUnionsRegionCorners() {
        let bounds = AIExplanationGeometry.groupBounds(for: [
            NSRect(x: 10, y: 20, width: 30, height: 8),
            NSRect(x: 50, y: 5, width: 12, height: 10)
        ])

        #expect(bounds == NSRect(x: 10, y: 5, width: 52, height: 23))
    }

    @Test
    func emptyRegionsHaveNoGroupBounds() {
        #expect(AIExplanationGeometry.groupBounds(for: []) == nil)
    }

    @Test
    func hoverContainsUsesAsymmetricSlop() {
        let bounds = NSRect(x: 10, y: 20, width: 30, height: 10)

        #expect(AIExplanationGeometry.hoverContains(NSPoint(x: 5, y: 12), in: bounds))
        #expect(AIExplanationGeometry.hoverContains(NSPoint(x: 44.9, y: 37.9), in: bounds))
        #expect(!AIExplanationGeometry.hoverContains(NSPoint(x: 4.9, y: 12), in: bounds))
        #expect(!AIExplanationGeometry.hoverContains(NSPoint(x: 45.1, y: 38), in: bounds))
    }

}

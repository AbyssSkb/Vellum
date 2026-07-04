import AppKit
import Testing
@testable import VellumCore

@Suite("Markdown floating overlay layout")
struct MarkdownFloatingOverlayLayoutTests {
    @Test
    func flippedViewsPlaceOverlayNearTopInset() {
        let frame = MarkdownFloatingOverlayLayout.frame(
            in: NSRect(x: 0, y: 0, width: 800, height: 600),
            size: NSSize(width: 360, height: 180),
            isFlipped: true,
            backingScale: 2
        )

        #expect(frame.origin.y == 76)
        #expect(frame.midX == 400)
    }

    @Test
    func nonFlippedViewsPlaceOverlayNearTopInset() {
        let frame = MarkdownFloatingOverlayLayout.frame(
            in: NSRect(x: 0, y: 0, width: 800, height: 600),
            size: NSSize(width: 360, height: 180),
            isFlipped: false,
            backingScale: 2
        )

        #expect(frame.origin.y == 344)
        #expect(frame.midX == 400)
    }
}

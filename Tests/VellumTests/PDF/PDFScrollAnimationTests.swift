import AppKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF keyboard scroll animation")
struct PDFScrollAnimationTests {
    @Test(arguments: [false, true], [CGFloat(-60), CGFloat(60)])
    func keyboardScrollAccountsForDocumentCoordinates(isFlipped: Bool, delta: CGFloat) throws {
        _ = NSApplication.shared
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        defer { view.stopScrollAnimation() }
        let scrollView = try #require(view.pdfScrollView)
        let documentView = ScrollDirectionDocumentView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000))
        documentView.flippedCoordinates = isFlipped
        scrollView.documentView = documentView
        let origin = NSPoint(x: 300, y: 400)
        scrollView.contentView.scroll(to: origin)

        view.vimScroll(x: 40, y: delta)
        view.vimScroll(x: 40, y: delta)
        let target = NSPoint(x: origin.x + 80, y: origin.y + (isFlipped ? -delta : delta) * 2)
        #expect(view.animationState.scrollTargetOrigin == target)
        view.animationState.scrollTimer?.invalidate()
        for _ in 0..<60 {
            view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepScrollAnimation(in: scrollView)
        }
        #expect(scrollView.contentView.bounds.origin == target)
    }

    @Test(arguments: [CGFloat(600), CGFloat(1_200)])
    func scrollAnimationReclampsAfterViewportResize(viewportLength: CGFloat) {
        _ = NSApplication.shared
        let view = VellumPDFView()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000))
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 800, y: 800))
        view.animationState.scrollTargetOrigin = NSPoint(x: 800, y: 800)
        clipView.setFrameSize(NSSize(width: viewportLength, height: viewportLength))

        view.stepScrollAnimation(in: scrollView)

        let maximum = max(0, 1_000 - viewportLength)
        if viewportLength < 1_000 {
            let expectedTarget = NSPoint(x: maximum, y: maximum)
            #expect(view.animationState.scrollTargetOrigin == expectedTarget
                || (view.animationState.scrollTargetOrigin == nil && clipView.bounds.origin == expectedTarget))
            #expect(clipView.bounds.origin.x >= 0 && clipView.bounds.origin.x <= maximum)
            #expect(clipView.bounds.origin.y >= 0 && clipView.bounds.origin.y <= maximum)
        } else {
            #expect(clipView.bounds.contains(NSRect(x: 0, y: 0, width: 1_000, height: 1_000)))
        }
    }

    @Test
    func scrollAnimationReachesFractionalTarget() {
        _ = NSApplication.shared
        let view = VellumPDFView()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000))
        let target = NSPoint(x: 123.4, y: 456.65)
        view.animationState.scrollTargetOrigin = target
        for _ in 0..<60 {
            view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepScrollAnimation(in: scrollView)
        }
        #expect(scrollView.contentView.bounds.origin == target)
        #expect(view.animationState.scrollTargetOrigin == nil)
    }
}

@MainActor
private final class ScrollDirectionDocumentView: NSView {
    var flippedCoordinates = false
    override var isFlipped: Bool { flippedCoordinates }
}

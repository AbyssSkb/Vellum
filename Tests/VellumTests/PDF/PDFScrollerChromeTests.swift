import Testing
import AppKit
@testable import VellumCore

@Suite("PDF scroller chrome")
struct PDFScrollerChromeTests {
    @Test
    @MainActor
    func configuredPDFScrollViewRejectsLegacyScrollerStyle() throws {
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.configurePDFScrollers()

        guard let scrollView = view.pdfScrollView else {
            Issue.record("Expected PDFView to contain an NSScrollView")
            return
        }

        scrollView.scrollerStyle = .legacy

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.drawsBackground == false)
    }

    @Test
    @MainActor
    func overlayLockOnlyAppliesToConfiguredPDFScroller() throws {
        let untouchedScrollView = NSScrollView()
        untouchedScrollView.scrollerStyle = .legacy
        #expect(untouchedScrollView.scrollerStyle == .legacy)

        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.configurePDFScrollers()

        guard let scrollView = view.pdfScrollView else {
            Issue.record("Expected PDFView to contain an NSScrollView")
            return
        }

        scrollView.scrollerStyle = .legacy
        #expect(scrollView.scrollerStyle == .overlay)
    }
}

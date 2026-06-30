import Testing
import AppKit
@testable import VellumCore

@Suite("PDF scroller chrome")
struct PDFScrollerChromeTests {
    @Test
    @MainActor
    func preferredScrollerStyleNotificationRestoresOverlayChrome() async throws {
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.configurePDFScrollers()

        guard let scrollView = view.pdfScrollView else {
            Issue.record("Expected PDFView to contain an NSScrollView")
            return
        }

        view.startObservingScrollerStyleChanges()
        defer { view.stopObservingScrollerStyleChanges() }

        scrollView.scrollerStyle = .legacy
        #expect(scrollView.scrollerStyle == .legacy)

        NotificationCenter.default.post(
            name: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil
        )
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.drawsBackground == false)
    }
}

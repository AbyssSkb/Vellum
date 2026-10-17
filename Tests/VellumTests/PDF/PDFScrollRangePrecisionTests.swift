import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF scroll range precision")
struct PDFScrollRangePrecisionTests {
    @Test(arguments: [CGFloat(0.125), 0.25, 0.49]) @MainActor
    func fittedSinglePageHasNoSubpixelScrollRange(overflow: CGFloat) throws {
        let (window, view) = try makeReader(pageCount: 1)
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let page = try #require(view.document?.page(at: 0))
        let documentView = try #require(scrollView.documentView)
        let paper = view.convert(view.convert(page.bounds(for: view.displayBox), from: page), to: documentView)
        // Replay PDFKit's fractional viewport rounding after a page-fit layout.
        clipView.setBoundsSize(NSSize(width: clipView.bounds.width, height: paper.height - overflow))

        let range = view.verticalScrollRange(in: scrollView)
        #expect(abs(range.upperBound - range.lowerBound) < 0.001)
    }

    @Test(arguments: [1, 3]) @MainActor
    func contentOverflowRemainsScrollable(pageCount: Int) throws {
        let (window, view) = try makeReader(pageCount: pageCount)
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        clipView.setBoundsSize(NSSize(width: clipView.bounds.width, height: clipView.bounds.height - 2))

        let range = view.verticalScrollRange(in: scrollView)
        #expect(range.upperBound - range.lowerBound > 1)
    }

    @MainActor
    private func makeReader(pageCount: Int) throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 900), for: .mediaBox)
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        let firstPage = try #require(document.page(at: 0))
        view.scaleFactor = try #require(view.pageFitScale(for: firstPage))
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        return (window, view)
    }
}

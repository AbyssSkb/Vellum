import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reader container layout")
struct PDFReaderContainerTests {
    @Test(arguments: [NSSize(width: 1_000, height: 700), NSSize(width: 700, height: 650)])
    func readerFillsTheContainerWithoutASidePane(size: NSSize) {
        _ = NSApplication.shared
        let reader = VellumPDFView(frame: NSRect(origin: .zero, size: size))
        let container = PDFReaderContainer(reader: reader)
        container.layoutSubtreeIfNeeded()

        #expect(reader.superview === container)
        #expect(reader.frame == container.bounds)
        #expect(container.subviews.count == 1)
    }

    @Test(arguments: [false, true])
    func resizingPreservesReadingAnchorAndZoomMode(fitWidth: Bool) async throws {
        let (window, container, page) = try makeReader()
        defer { close(window, container.reader) }
        let reader = container.reader
        await nextTestMainQueueTurn()
        reader.cancelPendingRestore()
        reader.autoScales = false
        if fitWidth {
            try #require(reader.applyWidthFitScaleNow(for: page))
        } else {
            reader.scaleFactor = 0.8
        }
        reader.layoutDocumentView()
        reader.centerBothAxes(on: PDFDestination(page: page, at: NSPoint(x: 306, y: 800)))
        let anchor = try #require(reader.centerDestination())
        let originalScale = reader.scaleFactor

        window.setContentSize(NSSize(width: 760, height: 600))
        container.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()

        try expectAnchor(anchor, in: reader)
        if fitWidth {
            let fitScale = try #require(reader.widthFitScale(for: page))
            #expect(abs(reader.scaleFactor - fitScale) < 0.002)
            #expect(reader.scaleFactor < originalScale)
        } else {
            #expect(reader.scaleFactor == originalScale)
            let scrollView = try #require(reader.pdfScrollView)
            #expect(scrollView.contentView.bounds.origin.x < 0)
        }

        window.setContentSize(NSSize(width: 1_000, height: 700))
        container.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()

        try expectAnchor(anchor, in: reader)
        #expect(abs(reader.scaleFactor - originalScale) < 0.002)
        #expect(reader.frame == container.bounds)
    }

    @Test
    func widthFitKeepsPaperTopAnchoredWhenTheContainerResizes() async throws {
        let (window, container, page) = try makeReader()
        defer { close(window, container.reader) }
        let reader = container.reader
        await nextTestMainQueueTurn()
        reader.cancelPendingRestore()
        try #require(reader.applyWidthFitScaleNow(for: page))
        reader.centerBothAxes(on: reader.topDestination(for: page), pageEdge: .top)

        window.setContentSize(NSSize(width: 760, height: 600))
        container.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()

        let scrollView = try #require(reader.pdfScrollView)
        let expectedTop = try #require(reader.pageEdgeOrigin(for: page, edge: .top, in: scrollView))
        #expect(abs(scrollView.contentView.bounds.origin.y - expectedTop) < 1)
    }

    private func expectAnchor(_ anchor: PDFDestination, in reader: VellumPDFView) throws {
        let current = try #require(reader.centerDestination())
        #expect(current.page === anchor.page)
        #expect(abs(current.point.x - anchor.point.x) < 2)
        #expect(abs(current.point.y - anchor.point.y) < 2)
    }

    private func makeReader() throws -> (NSWindow, PDFReaderContainer, PDFPage) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let reader = VellumPDFView(frame: try #require(window.contentView).bounds)
        reader.displayMode = .singlePageContinuous
        let document = PDFDocument()
        for _ in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 1_600), for: .mediaBox)
            document.insert(page, at: document.pageCount)
        }
        reader.document = document
        let container = PDFReaderContainer(reader: reader)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        reader.layoutDocumentView()
        return (window, container, try #require(document.page(at: 1)))
    }

    private func close(_ window: NSWindow, _ reader: VellumPDFView) {
        reader.cancelPendingRestore()
        reader.stopScrollAnimation()
        reader.stopZoomState()
        reader.readingPositionReportWorkItem?.cancel()
        reader.readerStateSaveWorkItem?.cancel()
        window.contentView = nil
        window.close()
    }
}

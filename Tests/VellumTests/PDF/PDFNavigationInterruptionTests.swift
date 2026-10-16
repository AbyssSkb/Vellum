import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF navigation interruption")
struct PDFNavigationInterruptionTests {
    @Test(arguments: [0, 90, 180, 270])
    @MainActor
    func firstPageAlignsPaperWithViewportTop(rotation: Int) async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 800, height: 1_100), for: .mediaBox)
            page.setBounds(NSRect(x: 40, y: 60, width: 600, height: 900), for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.cancelPendingRestore(); view.stopScrollAnimation(); view.stopZoomState() }
        view.displayMode = .singlePageContinuous
        view.document = document
        let firstPage = try #require(document.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let margins = view.pageBreakMargins

        view.vimGoToLastPage()
        await nextTestMainQueueTurn()
        view.vimGoToFirstPage()
        await nextTestMainQueueTurn()

        let paper = view.convert(firstPage.bounds(for: view.displayBox), from: firstPage)
        let viewport = view.convert(clipView.bounds, from: clipView)
        let gap = view.isFlipped ? paper.minY - viewport.minY : viewport.maxY - paper.maxY
        #expect(abs(gap) < 0.5)
        #expect(view.pageBreakMargins.top == margins.top)
        #expect(view.pageBreakMargins.bottom == margins.bottom)

        let documentView = try #require(scrollView.documentView)
        let documentPaper = view.convert(paper, to: documentView)
        // Native positioning may round to pixels; keyboard clamping keeps the exact paper edge.
        let topOrigin = NSPoint(x: clipView.bounds.origin.x, y: documentView.isFlipped
            ? documentPaper.minY : documentPaper.maxY - clipView.bounds.height)
        func scroll(_ delta: CGFloat) {
            view.vimScroll(x: 0, y: delta)
            for _ in 0..<60 {
                view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepScrollAnimation(in: scrollView)
            }
        }
        for distance in [CGFloat(60), clipView.bounds.height / 2, clipView.bounds.height] {
            scroll(distance)
            #expect(abs(clipView.bounds.origin.y - topOrigin.y) < 0.001)
            #expect(abs(clipView.bounds.origin.x - topOrigin.x) < 0.001)
        }
        scroll(-60)
        #expect(abs(clipView.bounds.origin.y - topOrigin.y) > 50)
        scroll(clipView.bounds.height / 2)
        #expect(abs(clipView.bounds.origin.y - topOrigin.y) < 0.001)
    }

    @Test
    @MainActor
    func newerInteractionCancelsDeferredPositionCorrections() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 1_000, height: 1_200), for: .mediaBox)
            document.insert(page, at: index)
        }
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.displayMode = .singlePageContinuous
        view.document = document
        view.scaleFactor = 1
        view.layoutDocumentView()
        defer { view.cancelPendingRestore(); view.stopScrollAnimation(); view.stopZoomState() }
        let clipView = try #require(view.pdfScrollView?.contentView)
        let destination = PDFDestination(page: try #require(document.page(at: 2)), at: NSPoint(x: 500, y: 600))
        let userOrigin = NSPoint(x: 123, y: 456)

        for command in 0..<4 {
            switch command {
            case 0: view.vimGoToFirstPage()
            case 1: view.vimGoToLastPage()
            case 2: view.vimGoToPage(3)
            default: view.vimGoToDestination(destination)
            }
            view.cancelPendingRestore()
            clipView.scroll(to: userOrigin)
            await nextTestMainQueueTurn()
            #expect(clipView.bounds.origin == userOrigin)
        }

        view.vimGoToDestination(destination)
        DispatchQueue.main.async {
            view.cancelPendingRestore()
            clipView.scroll(to: userOrigin)
        }
        await nextTestMainQueueTurn()
        await nextTestMainQueueTurn()
        #expect(clipView.bounds.origin == userOrigin)
    }

}

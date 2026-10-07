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
        view.displayMode = .singlePageContinuous
        view.document = document
        let firstPage = try #require(document.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        let clipView = try #require(view.pdfScrollView?.contentView)
        let margins = view.pageBreakMargins

        view.vimGoToLastPage()
        await drainMainQueue()
        view.vimGoToFirstPage()
        await drainMainQueue()

        let paper = view.convert(firstPage.bounds(for: view.displayBox), from: firstPage)
        let viewport = view.convert(clipView.bounds, from: clipView)
        let gap = view.isFlipped ? paper.minY - viewport.minY : viewport.maxY - paper.maxY
        #expect(abs(gap) < 0.5)
        #expect(view.pageBreakMargins.top == margins.top)
        #expect(view.pageBreakMargins.bottom == margins.bottom)
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
            await drainMainQueue()
            #expect(clipView.bounds.origin == userOrigin)
        }

        view.vimGoToDestination(destination)
        DispatchQueue.main.async {
            view.cancelPendingRestore()
            clipView.scroll(to: userOrigin)
        }
        await drainMainQueue()
        await drainMainQueue()
        #expect(clipView.bounds.origin == userOrigin)
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

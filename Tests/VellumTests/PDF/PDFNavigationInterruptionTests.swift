import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF navigation interruption")
struct PDFNavigationInterruptionTests {
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

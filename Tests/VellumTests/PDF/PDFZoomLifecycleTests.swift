import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF zoom lifecycle")
struct PDFZoomLifecycleTests {
    @Test @MainActor
    func initialRestoreSurvivesMountingIntoDetachedHierarchy() async throws {
        _ = NSApplication.shared
        let view = makeReader()
        view.restore(.initial)
        #expect(view.pendingRestoreAction != nil)

        let container = NSView(frame: view.frame)
        container.addSubview(view)
        let window = makeWindow()
        window.contentView = container
        defer { view.cancelPendingRestore(); window.close() }
        for _ in 0..<30 {
            if view.pendingRestoreAction == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(view.pendingRestoreAction == nil)
        #expect(view.scaleFactor < 1)
    }

    @Test @MainActor
    func dismantlingCancelsAnimationsAndDeferredRestore() throws {
        _ = NSApplication.shared
        let view = makeReader()
        let window = makeWindow()
        window.contentView = view
        defer { window.close() }
        view.vimZoom(to: 2)
        let zoomTimer = try #require(view.animationState.zoomTimer)
        let scrollView = try #require(view.pdfScrollView)
        view.animationState.scrollTargetOrigin = NSPoint(x: 0, y: 120)
        view.ensureScrollAnimation(in: scrollView)
        let scrollTimer = try #require(view.animationState.scrollTimer)
        view.pendingRestoreAction = .initial(generation: view.restoreGeneration)
        let generation = view.restoreGeneration

        PDFReader.dismantleNSView(view, coordinator: ())

        #expect(!zoomTimer.isValid)
        #expect(!scrollTimer.isValid)
        #expect(view.animationState.zoomTargetScale == nil)
        #expect(view.animationState.scrollTargetOrigin == nil)
        #expect(view.pendingRestoreAction == nil)
        #expect(view.restoreGeneration > generation)
    }

    @MainActor
    private func makeReader() -> VellumPDFView {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 1_600, height: 2_400), for: .mediaBox)
        document.insert(page, at: 0)
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        return view
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}

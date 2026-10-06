import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF zoom lifecycle")
struct PDFZoomLifecycleTests {
    @Test(arguments: [false, true]) @MainActor
    func restoredSessionUsesCurrentViewportWithoutLosingHorizontalPan(zoomed: Bool) async throws {
        _ = NSApplication.shared
        let previousView = makeReader()
        let previousWindow = makeWindow()
        previousWindow.contentView = previousView
        if zoomed {
            previousView.scaleFactor = 1.5
            previousView.layoutDocumentView()
        } else {
            #expect(previousView.applyWidthFitScaleNow())
        }
        let previousScrollView = try #require(previousView.pdfScrollView)
        let previousClip = previousScrollView.contentView
        let savedOrigin = previousClip.constrainBoundsRect(NSRect(
            origin: NSPoint(x: zoomed ? 275 : 0, y: 300), size: previousClip.bounds.size
        )).origin
        previousClip.scroll(to: savedOrigin)
        previousScrollView.reflectScrolledClipView(previousClip)
        let encoded = try JSONEncoder().encode(try #require(previousView.snapshot()))
        let savedSnapshot = try JSONDecoder().decode(ReaderSnapshot.self, from: encoded)
        previousWindow.close()

        let view = makeReader()
        view.restore(savedSnapshot)
        let window = makeWindow()
        window.setContentSize(NSSize(width: 1_000, height: 600))
        window.contentView = view
        defer { view.cancelPendingRestore(); window.close() }
        for _ in 0..<30 {
            if view.pendingRestoreAction == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(view.pendingRestoreAction == nil)
        let clip = try #require(view.pdfScrollView?.contentView)
        #expect(abs(clip.bounds.origin.y - savedOrigin.y) < 1)
        if zoomed {
            #expect(abs(clip.bounds.origin.x - savedOrigin.x) < 1)
        } else {
            let page = try #require(view.document?.page(at: 0))
            let pageCenter = view.convert(view.pageCenterDestination(for: page).point, from: page)
            #expect(abs(pageCenter.x - view.bounds.midX) < 1)
        }
    }

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

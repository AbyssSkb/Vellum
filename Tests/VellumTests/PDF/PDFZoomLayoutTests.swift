import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("PDF zoom layout")
struct PDFZoomLayoutTests {
    @Test @MainActor
    func widthFitInReaderLeavesNoHorizontalScrollForUniformPages() throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 900), for: .mediaBox)
            document.insert(page, at: index)
        }
        let defaults = try #require(UserDefaults(suiteName: "WidthFitTests.\(UUID().uuidString)"))
        let appState = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false
        ))
        let tab = PDFTab(url: URL(fileURLWithPath: "/tmp/width-fit-test.pdf"), document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hostingView = NSHostingView(rootView: PDFReader(
            tabID: tab.id, document: document, snapshot: nil, isActive: true
        ).environmentObject(appState))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let view = try #require(appState.activeReaderController as? VellumPDFView)
        defer { view.stopZoomState() }
        view.vimZoomToFit()
        view.applyZoomScale(try #require(view.animationState.zoomTargetScale))
        let scrollView = try #require(view.pdfScrollView)
        let documentView = try #require(scrollView.documentView)
        #expect(abs(documentView.bounds.width - scrollView.contentView.bounds.width) < 0.5)
        let page = try #require(document.page(at: 0))
        let paper = view.convert(page.bounds(for: view.displayBox), from: page)
        #expect(abs(paper.minX - view.bounds.minX) < 0.5)
        #expect(abs(paper.maxX - view.bounds.maxX) < 0.5)
    }

    @Test @MainActor
    func unchangedZoomKeepsExistingPageViews() throws {
        let (window, view, _) = try makeReader()
        defer { view.stopZoomState(); window.close() }
        let documentView = try #require(view.pdfScrollView?.documentView)
        let pageViews = documentView.subviews.map { ObjectIdentifier($0) }
        #expect(!pageViews.isEmpty)

        view.applyZoomScale(view.scaleFactor)

        #expect(documentView.subviews.map { ObjectIdentifier($0) } == pageViews)
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func zoomKeepsAnchorStableOnCroppedRotatedPages(rotation: Int) throws {
        let (window, view, page) = try makeReader(rotation: rotation)
        defer { view.stopZoomState(); window.close() }
        let anchor = try #require(view.centerDestination())
        view.animationState.zoomAnchor = anchor
        #expect(anchor.page === page)

        for scale: CGFloat in [1.2, 1.8, 2.4, 1.6, 0.8] {
            view.applyZoomScale(scale)
            let point = view.convert(anchor.point, from: page)
            #expect(abs(point.x - view.bounds.midX) < 1)
            #expect(abs(point.y - view.bounds.midY) < 1)
        }
    }

    @Test(arguments: [0, 90], [false, true]) @MainActor
    func fittingNarrowPageClearsHorizontalPan(rotation: Int, fitPage: Bool) throws {
        let (window, view, page) = try makeReader(rotation: rotation, narrow: true)
        defer { view.stopZoomState(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 900, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        #expect(view.centerDestination()?.page === page)
        let anchor = try #require(view.centerDestination())

        if fitPage {
            view.vimZoomToPageFit()
        } else {
            view.vimZoomToFit()
        }
        let target = try #require(view.animationState.zoomTargetScale)
        let pageSize = try #require(view.displaySize(for: page))
        let viewport = try #require(view.fitViewportSize())
        let expectedScale = fitPage
            ? min(viewport.width / pageSize.width, viewport.height / pageSize.height) * ZoomGeometry.fitMargin
            : viewport.width / pageSize.width
        #expect(abs(target - expectedScale) < 0.001)
        view.applyZoomScale(target)

        let pageCenter = view.convert(view.pageCenterDestination(for: page).point, from: page)
        #expect(abs(pageCenter.x - view.bounds.midX) < 1)
        if fitPage {
            #expect(abs(pageCenter.y - view.bounds.midY) < 1)
        } else {
            let point = view.convert(anchor.point, from: page)
            #expect(abs(point.y - view.bounds.midY) < 1)
            let paper = view.convert(page.bounds(for: view.displayBox), from: page)
            let viewportRect = view.convert(clipView.bounds, from: clipView)
            #expect(abs(paper.minX - viewportRect.minX) < 0.5)
            #expect(abs(paper.maxX - viewportRect.maxX) < 0.5)
        }
    }

    @Test @MainActor
    func zoomCompletesPendingSnapshotBeforeChoosingBaseScale() throws {
        let (window, view, page) = try makeReader()
        defer { view.stopZoomState(); window.close() }
        let snapshot = ReaderSnapshot(pageIndex: 1, pointOnPage: view.pageCenterDestination(for: page).point,
                                      scrollOrigin: nil, scaleFactor: 2, autoScales: false)
        view.pendingRestoreAction = .snapshot(snapshot: snapshot, page: page, generation: view.restoreGeneration)

        view.vimZoom(by: 1.1)

        #expect(view.pendingRestoreAction == nil)
        #expect(view.scaleFactor == 2)
        #expect(view.animationState.zoomTargetScale == 2.2)
    }

    @MainActor
    private func makeReader(rotation: Int = 0, narrow: Bool = false) throws -> (NSWindow, VellumPDFView, PDFPage) {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 2000, height: 2400), for: .mediaBox)
            page.setBounds(index == 1
                ? NSRect(x: 40, y: 60, width: narrow ? 500 : 1000, height: narrow ? 700 : 1400)
                : NSRect(x: 0, y: 0, width: 2000, height: 2400), for: .cropBox)
            page.rotation = index == 1 ? rotation : 0
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
        view.scaleFactor = 1
        view.layoutDocumentView()
        let page = try #require(document.page(at: 1))
        view.centerBothAxes(on: view.pageCenterDestination(for: page))
        return (window, view, page)
    }
}

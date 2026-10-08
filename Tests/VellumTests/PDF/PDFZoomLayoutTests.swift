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
            ? min(viewport.width / pageSize.width, viewport.height / pageSize.height)
            : viewport.width / pageSize.width
        #expect(abs(target - expectedScale) < 0.001)
        view.applyZoomScale(target)

        let pageCenter = view.convert(view.pageCenterDestination(for: page).point, from: page)
        #expect(abs(pageCenter.x - view.bounds.midX) < 1)
        if fitPage {
            let paper = view.convert(page.bounds(for: view.displayBox), from: page)
            let viewportRect = view.convert(clipView.bounds, from: clipView)
            let gap = view.isFlipped ? paper.minY - viewportRect.minY : viewportRect.maxY - paper.maxY
            #expect(abs(gap) < 0.5)
        } else {
            let point = view.convert(anchor.point, from: page)
            #expect(abs(point.y - view.bounds.midY) < 1)
            let paper = view.convert(page.bounds(for: view.displayBox), from: page)
            let viewportRect = view.convert(clipView.bounds, from: clipView)
            #expect(abs(paper.minX - viewportRect.minX) < 0.5)
            #expect(abs(paper.maxX - viewportRect.maxX) < 0.5)
        }
    }

    @Test(arguments: [0, 90, 180, 270], [1, 3]) @MainActor
    func wholePageFitAlignsPaperTopWithoutClipping(rotation: Int, pageCount: Int) throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 800, height: 1_100), for: .mediaBox)
            page.setBounds(NSRect(x: 40, y: 60, width: 600, height: 900), for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)

        for index in 0..<pageCount {
            let page = try #require(document.page(at: index))
            view.autoScales = false
            view.scaleFactor = 1.2
            view.layoutDocumentView()
            view.centerBothAxes(on: view.pageCenterDestination(for: page))
            #expect(view.currentPageState()?.page === page)
            view.vimZoomToPageFit()
            let target = try #require(view.animationState.zoomTargetScale)
            for _ in 0..<60 {
                view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepZoomAnimation()
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            #expect(abs(view.scaleFactor - target) < 0.001)
            #expect(!view.animationState.hasActiveZoomTimer)

            func expectWholePaperAtTop() {
                let paper = view.convert(page.bounds(for: view.displayBox), from: page)
                let viewport = view.convert(clipView.bounds, from: clipView)
                let gap = view.isFlipped ? paper.minY - viewport.minY : viewport.maxY - paper.maxY
                #expect(abs(gap) < 0.5)
                #expect(abs(paper.midX - viewport.midX) < 0.5)
                #expect(paper.minX >= viewport.minX - 0.5 && paper.maxX <= viewport.maxX + 0.5)
                #expect(paper.minY >= viewport.minY - 0.5 && paper.maxY <= viewport.maxY + 0.5)
                #expect(abs(min(viewport.width - paper.width, viewport.height - paper.height)) < 0.5)
            }
            expectWholePaperAtTop()

            if index == 0 || index == pageCount - 1 {
                let origin = clipView.bounds.origin
                let upward: CGFloat = documentView.isFlipped ? -1 : 1
                let direction = index == 0 ? upward : -upward
                for distance in [CGFloat(60), clipView.bounds.height / 2, clipView.bounds.height] {
                    view.vimScroll(x: 0, y: direction * distance)
                    for _ in 0..<60 {
                        view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepScrollAnimation(in: scrollView)
                    }
                    #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                    expectWholePaperAtTop()
                }
            }
        }
    }

    @Test(arguments: [0, 90, 180, 270], [1, 3]) @MainActor
    func documentEdgesAlignPaperAndPreventFurtherOutwardScrolling(rotation: Int, pageCount: Int) async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 800, height: 1_100), for: .mediaBox)
            page.setBounds(NSRect(x: 40, y: 60, width: 600, height: 900), for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: pageCount - 1))

        func nativeScroll(_ delta: Int32, phase: CGScrollPhase? = nil, momentum: CGMomentumScrollPhase = .none) throws {
            let cgEvent = try #require(CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0
            ))
            cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: phase != nil || momentum != .none ? 1 : 0)
            if let phase {
                cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            }
            cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
            let event = try #require(NSEvent(cgEvent: cgEvent))
            scrollView.scrollWheel(with: event)
        }

        for fit in 0..<3 {
            for edge in [VellumPDFView.VerticalEdge.top, .bottom] {
                view.autoScales = false
                view.scaleFactor = 1.2
                view.layoutDocumentView()
                view.centerBothAxes(on: view.pageCenterDestination(for: firstPage))
                if fit == 1 { view.vimZoomToFit() } else { view.vimZoomToPageFit() }
                let target = try #require(view.animationState.zoomTargetScale)
                if fit == 2 {
                    view.applyZoomScale(target * 1.0005)
                    view.stepZoomAnimation()
                    #expect(view.animationState.hasActiveZoomTimer)
                } else {
                    for _ in 0..<60 {
                        view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepZoomAnimation()
                    }
                    try await Task.sleep(for: .milliseconds(30))
                }
                if edge == .top { view.vimGoToFirstPage() } else { view.vimGoToLastPage() }
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                let page = edge == .top ? firstPage : lastPage
                let paper = view.convert(page.bounds(for: view.displayBox), from: page)
                let viewport = view.convert(clipView.bounds, from: clipView)
                let gap = (edge == .top) == view.isFlipped
                    ? paper.minY - viewport.minY : viewport.maxY - paper.maxY
                #expect(abs(gap) < 0.5)

                let origin = clipView.bounds.origin
                let outward: CGFloat = (edge == .top) == documentView.isFlipped ? -1 : 1
                for distance in [CGFloat(60), clipView.bounds.height / 2, clipView.bounds.height] {
                    view.vimScroll(x: 0, y: outward * distance)
                    for _ in 0..<60 {
                        view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepScrollAnimation(in: scrollView)
                    }
                    #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                }
                if paper.height >= viewport.height - 0.5 {
                    clipView.scroll(to: NSPoint(x: origin.x, y: origin.y + outward * 30))
                    view.vimScroll(x: 0, y: outward * 60)
                    for _ in 0..<60 {
                        view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepScrollAnimation(in: scrollView)
                    }
                    #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                }
                let wheelDirection: Int32 = edge == .top ? 60 : -60
                try nativeScroll(wheelDirection, phase: .began)
                for _ in 0..<8 { try nativeScroll(wheelDirection, phase: .changed) }
                try nativeScroll(0, phase: .ended)
                try nativeScroll(wheelDirection, momentum: .begin)
                for _ in 0..<8 { try nativeScroll(wheelDirection, momentum: .continuous) }
                try nativeScroll(0, momentum: .end)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                let deferredBounds = clipView.constrainBoundsRect(NSRect(
                    origin: NSPoint(x: origin.x, y: origin.y + outward * 30), size: clipView.bounds.size
                ))
                clipView.scroll(to: deferredBounds.origin)
                scrollView.reflectScrolledClipView(clipView)
                try await Task.sleep(for: .milliseconds(200))
                #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                if edge == .top, paper.height > viewport.height + 0.5 {
                    try nativeScroll(-wheelDirection, phase: .began)
                    #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
                    try nativeScroll(wheelDirection * 2, phase: .changed)
                    try nativeScroll(0, phase: .ended)
                    try await Task.sleep(for: .milliseconds(200))
                    #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                }
            }
        }
    }

    @Test @MainActor
    func legacyWheelMovesInwardAndSettlesAtPaperTop() async throws {
        let (window, view, _) = try makeReader()
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let firstPage = try #require(view.document?.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        view.scrollToDocumentEdge(.top)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin

        func nativeScroll(_ delta: Int32) throws {
            let cgEvent = try #require(CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0
            ))
            scrollView.scrollWheel(with: try #require(NSEvent(cgEvent: cgEvent)))
        }
        try nativeScroll(-60)
        #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
        try nativeScroll(120)
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
        for _ in 0..<8 { try nativeScroll(60) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
    }

    @Test @MainActor
    func nativeDragSettlesAtPaperTopAndPreservesNewNavigation() async throws {
        let (window, view, _) = try makeReader()
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let firstPage = try #require(view.document?.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        view.scrollToDocumentEdge(.top)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let documentView = try #require(scrollView.documentView)
        let outward: CGFloat = documentView.isFlipped ? -1 : 1

        func dragOutward() {
            PDFNativeScrollBoundsConstraint.beginLiveScroll(in: scrollView)
            let bounds = clipView.constrainBoundsRect(NSRect(
                origin: NSPoint(x: origin.x, y: origin.y + outward * 30), size: clipView.bounds.size
            ))
            clipView.scroll(to: bounds.origin)
            scrollView.reflectScrolledClipView(clipView)
            PDFNativeScrollBoundsConstraint.endLiveScroll(in: scrollView)
        }
        dragOutward()
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
        dragOutward()
        view.vimGoToPage(2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(view.currentPageState()?.pageIndex == 1)
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

    @Test(arguments: [false, true]) @MainActor
    func newInteractionCancelsFinalPageFitTick(newZoom: Bool) throws {
        let (window, view, page) = try makeReader()
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.vimZoomToPageFit()
        let target = try #require(view.animationState.zoomTargetScale)
        view.applyZoomScale(target * 1.0005)
        view.stepZoomAnimation()
        #expect(view.scaleFactor == target)
        #expect(view.animationState.hasActiveZoomTimer)

        if newZoom {
            view.vimZoom(to: target * 2)
            #expect(view.animationState.zoomPageFitPhase == nil)
            for _ in 0..<60 {
                view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepZoomAnimation()
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            }
            let center = view.convert(view.pageCenterDestination(for: page).point, from: page)
            #expect(abs(center.y - view.bounds.midY) < 1)
        } else {
            let scrollView = try #require(view.pdfScrollView)
            view.vimScroll(x: 0, y: 100)
            let targetOrigin = try #require(view.animationState.scrollTargetOrigin)
            #expect(!view.animationState.hasActiveZoomTimer)
            #expect(view.animationState.zoomPageFitPhase == nil)
            for _ in 0..<60 {
                view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepScrollAnimation(in: scrollView)
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            }
            #expect(abs(scrollView.contentView.bounds.origin.y - targetOrigin.y) < 0.001)
        }
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

import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("PDF zoom layout")
struct PDFZoomLayoutTests {
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)], [0, 90]) @MainActor
    func widthFitAfterZoomAndDocumentEdgeKeepsPaperAligned(scenario: (Bool, Bool), rotation: Int) async throws {
        let (quick, bottom) = scenario
        let (window, view, _) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let document = try #require(view.document)
        let page = try #require(document.page(at: bottom ? document.pageCount - 1 : 0))
        page.rotation = rotation
        view.layoutDocumentView()
        let clip = try #require(view.pdfScrollView?.contentView)

        func paperGap() -> CGFloat {
            let paper = view.convert(page.bounds(for: view.displayBox), from: page)
            let viewport = view.convert(clip.bounds, from: clip)
            return (bottom == view.isFlipped) ? viewport.maxY - paper.maxY : paper.minY - viewport.minY
        }
        func finishZoom(checkEdge: Bool = false) async {
            view.animationState.zoomTimer?.invalidate()
            for _ in 0..<60 {
                view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepZoomAnimation()
                await nextTestMainQueueTurn()
                if checkEdge { #expect(abs(paperGap()) < 0.5, "gap=\(paperGap())") }
                if view.animationState.zoomTargetScale == nil { break }
            }
        }
        view.vimZoomToFit()
        await finishZoom()
        view.vimZoom(by: 1.1)
        await finishZoom()
        if bottom { view.vimGoToLastPage() } else { view.vimGoToFirstPage() }
        if !quick { await nextTestMainQueueTurn() }
        view.vimZoomToFit()
        await finishZoom(checkEdge: true)
        await nextTestMainQueueTurn()

        let paper = view.convert(page.bounds(for: view.displayBox), from: page)
        let viewport = view.convert(clip.bounds, from: clip)
        let gap = (bottom == view.isFlipped) ? viewport.maxY - paper.maxY : paper.minY - viewport.minY
        #expect(abs(gap) < 0.5, "quick=\(quick), bottom=\(bottom), rotation=\(rotation), gap=\(gap), paper=\(paper), viewport=\(viewport)")
    }

    @Test @MainActor
    func widthFitKeepsIntermediateReadingPositionDuringAnimation() async throws {
        let (window, view, page) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let anchor = try #require(view.centerDestination())
        #expect(anchor.page === page)
        view.vimZoomToFit()
        view.animationState.zoomTimer?.invalidate()
        for _ in 0..<60 {
            view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepZoomAnimation()
            await nextTestMainQueueTurn()
            #expect(abs(view.convert(anchor.point, from: page).y - view.bounds.midY) < 1)
            if view.animationState.zoomTargetScale == nil { break }
        }
        #expect(view.animationState.zoomTargetScale == nil)
    }

    @Test(arguments: [1, 2], [false, true]) @MainActor
    func widthFitKeepsShortFinalPageAtBottom(pageCount: Int, quick: Bool) async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            let size = index == pageCount - 1 ? NSSize(width: 800, height: 160) : NSSize(width: 1000, height: 1600)
            page.setBounds(NSRect(origin: .zero, size: size), for: .mediaBox)
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1.4
        view.layoutDocumentView()
        await nextTestMainQueueTurn()
        view.vimGoToLastPage()
        if !quick { await nextTestMainQueueTurn() }
        let lastPage = try #require(document.page(at: pageCount - 1))
        let clip = try #require(view.pdfScrollView?.contentView)
        if pageCount > 1 { #expect(view.centerDestination()?.page !== lastPage) }
        view.vimZoomToFit()
        #expect(view.animationState.zoomAnchor?.page === lastPage)
        view.animationState.zoomTimer?.invalidate()
        for _ in 0..<60 {
            view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepZoomAnimation()
            await nextTestMainQueueTurn()
            let paper = view.convert(lastPage.bounds(for: view.displayBox), from: lastPage)
            let viewport = view.convert(clip.bounds, from: clip)
            let gap = view.isFlipped ? viewport.maxY - paper.maxY : paper.minY - viewport.minY
            #expect(abs(gap) < 0.5, "gap=\(gap), scale=\(view.scaleFactor), phase=\(String(describing: view.animationState.zoomPageFitPhase)), paper=\(paper), viewport=\(viewport)")
            if view.animationState.zoomTargetScale == nil { break }
        }
        #expect(view.animationState.zoomTargetScale == nil)
        #expect(abs(view.scaleFactor - 1) < 0.001)
    }

    @Test(arguments: [1, 2], ["repair", "cancel", "zoom", "navigate", "wheel", "complete"]) @MainActor
    func shortPageZoomRepairsDeferredNativeRecentering(pageCount: Int, action: String) async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        if pageCount == 2 {
            let firstPage = PDFPage()
            firstPage.setBounds(NSRect(x: 0, y: 0, width: 1000, height: 1600), for: .mediaBox)
            document.insert(firstPage, at: 0)
        }
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 800, height: 160), for: .mediaBox)
        document.insert(page, at: pageCount - 1)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1.4
        view.layoutDocumentView()
        await nextTestMainQueueTurn()
        view.vimGoToLastPage()
        view.vimZoomToFit()
        view.animationState.zoomTimer?.invalidate()
        view.applyZoomScale(1.2)
        let scroll = try #require(view.pdfScrollView)
        let clip = scroll.contentView
        view.configurePDFScrollersIfNeeded()
        let centered = pageCount == 1 ? clip.constrainBoundsRect(clip.bounds).origin
            : NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y - 2)
        let edge = try #require(view.pageEdgeOrigin(for: page, edge: .bottom, in: scroll))
        #expect(abs(centered.y - edge) > 1)
        switch action {
        case "cancel": view.stopZoomState()
        case "zoom":
            view.vimZoom(by: 1.1)
            view.animationState.zoomTimer?.invalidate()
        case "navigate": view.vimGoToFirstPage()
        case "wheel":
            PDFNativeScrollBoundsConstraint.install(on: scroll, for: view)
            let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                              wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
            let event = try #require(NSEvent(cgEvent: cgEvent))
            PDFNativeScrollBoundsConstraint.withNativeScroll(on: scroll, event: event) {}
        case "complete":
            view.animationState.zoomTargetScale = view.scaleFactor
            view.stepZoomAnimation()
        default: break
        }
        if action == "repair" { await nextTestMainQueueTurn() }
        let expected = action == "repair" || action == "complete" ? edge : centered.y
        for _ in 0..<3 {
            clip.scroll(to: centered)
            scroll.reflectScrolledClipView(clip)
            #expect(abs(clip.bounds.origin.x - centered.x) < 0.5)
            #expect(abs(clip.bounds.origin.y - expected) < 0.5)
        }
        await nextTestMainQueueTurn()
        if action != "navigate" { #expect(abs(clip.bounds.origin.y - expected) < 0.5) }
    }

    @Test(arguments: [CGFloat(-40), CGFloat(40)]) @MainActor
    func horizontalScrollDoesNotMoveWidthFittedPage(delta: CGFloat) throws {
        let (window, view, page) = try makeReader(narrow: true)
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        view.vimZoomToFit()
        view.applyZoomScale(try #require(view.animationState.zoomTargetScale))
        view.stopZoomState()
        let initialOrigin = scrollView.contentView.bounds.origin.x
        let initialPaper = view.convert(page.bounds(for: view.displayBox), from: page)

        view.vimScroll(x: delta, y: 0)
        view.animationState.scrollTimer?.invalidate()
        for _ in 0..<60 {
            view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepScrollAnimation(in: scrollView)
        }

        #expect(abs(scrollView.contentView.bounds.origin.x - initialOrigin) < 0.5)
        let paper = view.convert(page.bounds(for: view.displayBox), from: page)
        #expect(abs(paper.minX - initialPaper.minX) < 0.5)
    }

    @Test(arguments: [CGFloat(-40), CGFloat(40)]) @MainActor
    func horizontalScrollStillMovesEnlargedPage(delta: CGFloat) throws {
        let (window, view, page) = try makeReader(narrow: true)
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        view.vimZoomToFit()
        view.applyZoomScale(try #require(view.animationState.zoomTargetScale) * 1.5)
        view.stopZoomState()
        let origin = scrollView.contentView.bounds.origin.x
        #expect(view.currentPageState()?.page === page)

        view.vimScroll(x: delta, y: 0)
        #expect(abs(try #require(view.animationState.scrollTargetOrigin).x - (origin + delta)) < 0.5)
    }

    @Test(arguments: [CGFloat(-40), CGFloat(40)], [CGFloat(-300), CGFloat(300)]) @MainActor
    func horizontalScrollDoesNotReverseOutsideCurrentPage(delta: CGFloat, offset: CGFloat) throws {
        let (window, view, page) = try makeReader(narrow: true)
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        view.vimZoomToFit()
        view.applyZoomScale(try #require(view.animationState.zoomTargetScale) * 1.5)
        view.stopZoomState()
        let clip = scrollView.contentView
        let center = clip.bounds.origin
        clip.scroll(to: NSPoint(x: center.x + offset, y: center.y))
        let origin = clip.bounds.origin.x
        let documentView = try #require(scrollView.documentView)
        let paper = view.convert(view.convert(page.bounds(for: view.displayBox), from: page), to: documentView)
        let minimum = paper.minX
        let maximum = paper.maxX - clip.bounds.width
        #expect(offset < 0 ? origin < minimum : origin > maximum)

        view.vimScroll(x: delta, y: 0)
        let movement = try #require(view.animationState.scrollTargetOrigin).x - origin
        let expectedMovement: CGFloat = offset * delta < 0 ? delta : 0
        #expect(abs(movement - expectedMovement) < 0.001)
    }

    @Test(arguments: [CGFloat(-40), CGFloat(40)]) @MainActor
    func horizontalScrollCanReachWiderVisibleAdjacentPage(delta: CGFloat) throws {
        let (window, view, page) = try makeReader(narrow: true)
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        let documentView = try #require(scrollView.documentView)
        let previousPage = try #require(view.document?.page(at: 0))
        view.vimZoomToFit()
        view.applyZoomScale(try #require(view.animationState.zoomTargetScale))
        view.stopZoomState()
        let narrow = view.convert(view.convert(page.bounds(for: view.displayBox), from: page), to: documentView)
        let wide = view.convert(view.convert(previousPage.bounds(for: view.displayBox), from: previousPage), to: documentView)
        let clip = scrollView.contentView
        let y = wide.midY < narrow.midY ? narrow.minY - 100 : narrow.maxY - clip.bounds.height + 100
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        #expect(view.currentPageState()?.page === page)
        #expect(wide.maxY > clip.bounds.minY && wide.minY < clip.bounds.maxY)
        let origin = clip.bounds.origin.x

        view.vimScroll(x: delta, y: 0)
        #expect(abs(try #require(view.animationState.scrollTargetOrigin).x - (origin + delta)) < 0.5)
        view.vimScroll(x: delta * 10000, y: 0)
        let boundary = delta < 0 ? wide.minX : wide.maxX - clip.bounds.width
        #expect(abs(try #require(view.animationState.scrollTargetOrigin).x - boundary) < 0.5)
    }

    @Test @MainActor
    func widthFitInReaderLeavesNoHorizontalScrollForUniformPages() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 900), for: .mediaBox)
            document.insert(page, at: index)
        }
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
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
        try await waitForTestCondition("width-fit reader mounts and restores") {
            guard let reader = appState.activeReaderController as? VellumPDFView else { return false }
            return reader.window === window && reader.pendingRestoreAction == nil
        }
        let view = try #require(appState.activeReaderController as? VellumPDFView)
        defer {
            view.saveBeforeDismantle = nil
            view.cancelPendingRestore()
            view.stopZoomState()
            view.readerStateSaveWorkItem?.cancel()
        }
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
        defer { view.cancelPendingRestore(); view.stopZoomState(); window.close() }
        let documentView = try #require(view.pdfScrollView?.documentView)
        let pageViews = documentView.subviews.map { ObjectIdentifier($0) }
        #expect(!pageViews.isEmpty)

        view.applyZoomScale(view.scaleFactor)

        #expect(documentView.subviews.map { ObjectIdentifier($0) } == pageViews)
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func zoomKeepsAnchorStableOnCroppedRotatedPages(rotation: Int) throws {
        let (window, view, page) = try makeReader(rotation: rotation)
        defer { view.cancelPendingRestore(); view.stopZoomState(); window.close() }
        let anchor = try #require(view.centerDestination())
        view.animationState.zoomAnchor = anchor
        #expect(anchor.page === page)
        view.minScaleFactor = 0.5
        view.maxScaleFactor = 3
        let initialScale = view.scaleFactor
        let initialPaper = view.convert(page.bounds(for: view.displayBox), from: page)
        let scales: [(requested: CGFloat, expected: CGFloat)] = [
            (1.2, 1.2), (1.8, 1.8), (2.4, 2.4), (1.6, 1.6), (0.8, 0.8), (0.25, 0.5), (4, 3)
        ]

        for (requestedScale, expectedScale) in scales {
            view.applyZoomScale(requestedScale)
            #expect(abs(view.scaleFactor - expectedScale) < 0.000001)
            #expect(abs(try #require(view.snapshot()).scaleFactor - expectedScale) < 0.000001)
            let paper = view.convert(page.bounds(for: view.displayBox), from: page)
            #expect(abs(paper.width - initialPaper.width * expectedScale / initialScale) < 1)
            #expect(abs(paper.height - initialPaper.height * expectedScale / initialScale) < 1)
            let point = view.convert(anchor.point, from: page)
            #expect(abs(point.x - view.bounds.midX) < 1)
            #expect(abs(point.y - view.bounds.midY) < 1)
        }
    }

    @Test(arguments: [0, 90], [false, true]) @MainActor
    func fittingNarrowPageClearsHorizontalPan(rotation: Int, fitPage: Bool) throws {
        let (window, view, page) = try makeReader(rotation: rotation, narrow: true)
        defer { view.cancelPendingRestore(); view.stopZoomState(); window.close() }
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
    func wholePageFitAlignsPaperTopWithoutClipping(rotation: Int, pageCount: Int) async throws {
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
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView

        for index in 0..<pageCount {
            let page = try #require(document.page(at: index))
            view.autoScales = false
            view.scaleFactor = 1.2
            view.layoutDocumentView()
            view.centerBothAxes(on: view.pageCenterDestination(for: page))
            #expect(view.currentPageState()?.page === page)
            view.vimZoomToPageFit()
            let target = try #require(view.animationState.zoomTargetScale)
            view.animationState.zoomTimer?.invalidate()
            for _ in 0..<60 {
                view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepZoomAnimation()
                await nextTestMainQueueTurn()
                if view.animationState.zoomTargetScale == nil { break }
            }
            await nextTestMainQueueTurn()
            #expect(abs(view.scaleFactor - target) < 0.001)
            #expect(view.animationState.zoomTargetScale == nil)

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
                let direction: CGFloat = index == 0 ? 1 : -1
                for distance in [CGFloat(60), clipView.bounds.height / 2, clipView.bounds.height] {
                    view.vimScroll(x: 0, y: direction * distance)
                    view.animationState.scrollTimer?.invalidate()
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

    @Test @MainActor
    func zoomCompletesPendingSnapshotBeforeChoosingBaseScale() throws {
        let (window, view, page) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); window.close() }
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

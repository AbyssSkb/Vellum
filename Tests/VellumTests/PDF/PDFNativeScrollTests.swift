import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF native scroll settlement")
struct PDFNativeScrollTests {
    @Test(arguments: ["j", "k", "d", "u", "D", "U"]) @MainActor
    func vimKeysMoveInReadingDirection(key: String) async throws {
        let (window, view, page) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        try await waitForNativeLayout(in: view, page: page)
        view.centerBothAxes(on: view.pageCenterDestination(for: page))
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
        let tab = PDFTab(url: URL(fileURLWithPath: "/tmp/scroll-direction.pdf"), document: view.document)
        _ = appState.tabStore.openInNewTabs([tab])
        appState.setActiveReaderController(view, for: tab.id)
        let scrollView = try #require(view.pdfScrollView)
        let before = try #require(view.currentPageState()).pointOnPage.y

        VimCommandDispatcher().perform(try #require(VimKeyMap.command(for: key)), on: appState)
        view.animationState.scrollTimer?.invalidate()
        for _ in 0..<60 {
            view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepScrollAnimation(in: scrollView)
        }

        let after = try #require(view.currentPageState()).pointOnPage.y
        if ["j", "d", "D"].contains(key) {
            #expect(after < before)
        } else {
            #expect(after > before)
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
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: pageCount - 1))

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
                    view.animationState.zoomTimer?.invalidate()
                    for _ in 0..<60 {
                        view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepZoomAnimation()
                        await nextTestMainQueueTurn()
                        if view.animationState.zoomTargetScale == nil { break }
                    }
                    #expect(view.animationState.zoomTargetScale == nil)
                }
                if edge == .top { view.vimGoToFirstPage() } else { view.vimGoToLastPage() }
                await nextTestMainQueueTurn()
                try await waitForNativeLayout(in: view, page: edge == .top ? firstPage : lastPage)
                let page = edge == .top ? firstPage : lastPage
                let paper = view.convert(page.bounds(for: view.displayBox), from: page)
                let viewport = view.convert(clipView.bounds, from: clipView)
                let gap = (edge == .top) == view.isFlipped
                    ? paper.minY - viewport.minY : viewport.maxY - paper.maxY
                #expect(abs(gap) < 0.5)

                let origin = clipView.bounds.origin
                let outward: CGFloat = edge == .top ? 1 : -1
                let outwardCoordinate = documentView.isFlipped ? -outward : outward
                for distance in [CGFloat(60), clipView.bounds.height / 2, clipView.bounds.height] {
                    view.vimScroll(x: 0, y: outward * distance)
                    view.animationState.scrollTimer?.invalidate()
                    for _ in 0..<60 {
                        view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepScrollAnimation(in: scrollView)
                    }
                    #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                }
                if paper.height >= viewport.height - 0.5 {
                    clipView.scroll(to: NSPoint(x: origin.x, y: origin.y + outwardCoordinate * 30))
                    view.vimScroll(x: 0, y: outward * 60)
                    view.animationState.scrollTimer?.invalidate()
                    for _ in 0..<60 {
                        view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                        view.stepScrollAnimation(in: scrollView)
                    }
                    #expect(abs(clipView.bounds.origin.y - origin.y) < 0.001)
                }
                let wheelDirection: Int32 = edge == .top ? 60 : -60
                try sendNativeScroll(wheelDirection, to: scrollView, phase: .began)
                for _ in 0..<8 { try sendNativeScroll(wheelDirection, to: scrollView, phase: .changed) }
                try sendNativeScroll(0, to: scrollView, phase: .ended)
                try sendNativeScroll(wheelDirection, to: scrollView, momentum: .begin)
                for _ in 0..<8 { try sendNativeScroll(wheelDirection, to: scrollView, momentum: .continuous) }
                try sendNativeScroll(0, to: scrollView, momentum: .end)
                await nextTestMainQueueTurn()
                let deferredBounds = clipView.constrainBoundsRect(NSRect(
                    origin: NSPoint(x: origin.x, y: origin.y + outwardCoordinate * 30), size: clipView.bounds.size
                ))
                clipView.scroll(to: deferredBounds.origin)
                scrollView.reflectScrolledClipView(clipView)
                try await waitForSettlement(of: clipView, at: origin.y)
                if edge == .top, paper.height > viewport.height + 0.5 {
                    try sendNativeScroll(-wheelDirection, to: scrollView, phase: .began)
                    #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
                    try sendNativeScroll(wheelDirection * 2, to: scrollView, phase: .changed)
                    try sendNativeScroll(0, to: scrollView, phase: .ended)
                    try await waitForSettlement(of: clipView, at: origin.y)
                }
            }
        }
    }

    @Test @MainActor
    func legacyWheelMovesInwardAndSettlesAtPaperTop() async throws {
        let (window, view, _) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let firstPage = try #require(view.document?.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        try await waitForNativeLayout(in: view, page: firstPage)
        view.vimGoToFirstPage()
        try await waitForNativeLayout(in: view, page: firstPage)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let origin = try paperEdgeOrigin(in: view, page: firstPage, atBottom: false)

        try sendNativeScroll(-60, to: scrollView)
        #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
        try sendNativeScroll(120, to: scrollView)
        try await waitForSettlement(of: clipView, at: origin.y)
        for _ in 0..<8 { try sendNativeScroll(60, to: scrollView) }
        try await waitForSettlement(of: clipView, at: origin.y)
    }

    @Test @MainActor
    func nativeDragSettlesAtPaperTopAndPreservesNewNavigation() async throws {
        let (window, view, _) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let firstPage = try #require(view.document?.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        try await waitForNativeLayout(in: view, page: firstPage)
        view.vimGoToFirstPage()
        try await waitForNativeLayout(in: view, page: firstPage)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let origin = try paperEdgeOrigin(in: view, page: firstPage, atBottom: false)
        let documentView = try #require(scrollView.documentView)
        let outward: CGFloat = documentView.isFlipped ? -1 : 1

        func dragOutward() {
            PDFNativeScrollBoundsConstraint.beginLiveScroll(in: scrollView)
            let bounds = clipView.constrainBoundsRect(NSRect(
                origin: NSPoint(x: origin.x, y: origin.y + outward * 30), size: clipView.bounds.size
            ))
            clipView.scroll(to: bounds.origin)
            scrollView.reflectScrolledClipView(clipView)
            #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
            PDFNativeScrollBoundsConstraint.endLiveScroll(in: scrollView)
        }
        dragOutward()
        try await waitForSettlement(of: clipView, at: origin.y)
        dragOutward()
        view.vimGoToPage(2)
        try await waitForTestCondition("navigation reaches the second page") {
            view.currentPageState()?.pageIndex == 1
        }
        let navigatedOrigin = clipView.bounds.origin.y
        try await waitForSettlement(of: clipView, at: navigatedOrigin, quietInterval: 0.25)
        #expect(view.currentPageState()?.pageIndex == 1)
    }

    @Test(arguments: [false, true], [false, true]) @MainActor
    func nativeScrollSettlesAfterLiveEndAndLateLayoutWrites(atBottom: Bool, terminalWheelReachesScrollView: Bool) async throws {
        let (window, view, _) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let firstPage = try #require(view.document?.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        let edgePage = try #require(view.document?.page(at: atBottom ? view.document!.pageCount - 1 : 0))
        try await waitForNativeLayout(in: view, page: edgePage)
        if atBottom { view.vimGoToLastPage() } else { view.vimGoToFirstPage() }
        try await waitForNativeLayout(in: view, page: edgePage)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        let origin = try paperEdgeOrigin(in: view, page: edgePage, atBottom: atBottom)
        let outward: CGFloat = atBottom == documentView.isFlipped ? 1 : -1

        func nativeLayoutMovesOutsidePaper() {
            let bounds = clipView.constrainBoundsRect(NSRect(
                origin: NSPoint(x: origin.x, y: origin.y + outward * 30), size: clipView.bounds.size
            ))
            clipView.scroll(to: bounds.origin)
            scrollView.reflectScrolledClipView(clipView)
            #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
        }
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        try sendNativeScroll((atBottom ? -60 : 60), to: scrollView, phase: .began)
        try sendNativeScroll((atBottom ? -60 : 60), to: scrollView, phase: .changed)
        if terminalWheelReachesScrollView { try sendNativeScroll(0, to: scrollView, phase: .ended) }
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        nativeLayoutMovesOutsidePaper()
        try await waitForSettlement(of: clipView, at: origin.y)

        if terminalWheelReachesScrollView {
            nativeLayoutMovesOutsidePaper()
            try await waitForSettlement(of: clipView, at: origin.y)
        }
    }

    @Test(.enabled("Requires native scroll animations") {
        await MainActor.run { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    }, arguments: [false, true], ["settle", "scroll", "navigate", "shortPage"]) @MainActor
    func nativeEdgeSettlementHasContinuousFramesAndCanBeInterrupted(atBottom: Bool, scenario: String) async throws {
        let (window, view, _) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        if scenario == "shortPage" {
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 900), for: .mediaBox)
            page.rotation = 90
            document.insert(page, at: 0)
            view.document = document
            view.vimZoomToPageFit()
            view.animationState.zoomTimer?.invalidate()
            for _ in 0..<60 {
                view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepZoomAnimation()
                await nextTestMainQueueTurn()
                if view.animationState.zoomTargetScale == nil { break }
            }
            #expect(view.animationState.zoomTargetScale == nil)
        }
        let firstPage = try #require(view.document?.page(at: 0))
        if scenario != "shortPage" { #expect(view.applyWidthFitScaleNow(for: firstPage)) }
        let edgePage = try #require(view.document?.page(at: atBottom ? view.document!.pageCount - 1 : 0))
        try await waitForNativeLayout(in: view, page: edgePage)
        if atBottom { view.vimGoToLastPage() } else { view.vimGoToFirstPage() }
        try await waitForNativeLayout(in: view, page: edgePage)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        let edge: NSPoint
        if scenario == "shortPage" {
            edge = clipView.bounds.origin
        } else {
            edge = try paperEdgeOrigin(in: view, page: edgePage, atBottom: atBottom)
        }
        let outward: CGFloat = atBottom == documentView.isFlipped ? 1 : -1
        @MainActor final class Samples { var values: [CGFloat] = [] }
        let samples = Samples()
        let observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { _ in
            MainActor.assumeIsolated { samples.values.append(clipView.bounds.origin.y) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        PDFNativeScrollBoundsConstraint.beginLiveScroll(in: scrollView)
        let outside = clipView.constrainBoundsRect(NSRect(
            origin: NSPoint(x: edge.x, y: edge.y + outward * 30), size: clipView.bounds.size
        )).origin
        clipView.scroll(to: outside)
        scrollView.reflectScrolledClipView(clipView)
        let start = clipView.bounds.origin.y
        let gap = abs(start - edge.y)
        #expect(gap > 1)
        func isIntermediate(_ y: CGFloat) -> Bool {
            let distance = abs(y - edge.y)
            return distance > 0.5 && distance < gap - 0.5
        }
        samples.values = [start]
        PDFNativeScrollBoundsConstraint.endLiveScroll(in: scrollView)

        if scenario == "settle" || scenario == "shortPage" {
            try await waitForSettlement(of: clipView, at: edge.y)
            let intermediate = samples.values.filter(isIntermediate)
            #expect(Set(intermediate).count >= 2)
            let pixel = abs(clipView.convert(NSSize(width: 1, height: 1), from: nil).height)
                / window.backingScaleFactor
            for (previous, next) in zip(samples.values, samples.values.dropFirst()) {
                #expect(abs(next - edge.y) <= abs(previous - edge.y) + pixel)
            }
            let finalFrames = Array(samples.values.suffix(2))
            #expect(finalFrames.count == 2)
            if finalFrames.count == 2 {
                #expect(abs(finalFrames[1] - finalFrames[0]) <= pixel)
            }
            #expect(abs(clipView.bounds.origin.y - edge.y) < 0.001)
        } else {
            try await waitForTestCondition("native settlement produces an intermediate frame") {
                isIntermediate(clipView.bounds.origin.y)
            }
            if scenario == "scroll" {
                for phase in [CGScrollPhase.began, .ended] {
                    try sendNativeScroll(phase == .began ? (atBottom ? 60 : -60) : 0, to: scrollView, phase: phase)
                }
                let inward = clipView.bounds.origin.y
                #expect(abs(inward - edge.y) > gap)
                try await waitForSettlement(of: clipView, at: inward, quietInterval: 0.25)
            } else {
                view.vimGoToPage(2)
                try await waitForTestCondition("navigation interrupts native settlement") {
                    view.currentPageState()?.pageIndex == 1
                }
                let navigatedOrigin = clipView.bounds.origin.y
                try await waitForSettlement(of: clipView, at: navigatedOrigin, quietInterval: 0.25)
                #expect(view.currentPageState()?.pageIndex == 1)
            }
        }
    }

    @Test(.enabled("Requires Reduce Motion") {
        await MainActor.run { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    }, arguments: [false, true]) @MainActor
    func reducedMotionSettlesWithoutIntermediateFrames(atBottom: Bool) async throws {
        let (window, view, _) = try makeReader()
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let document = try #require(view.document)
        let firstPage = try #require(document.page(at: 0))
        #expect(view.applyWidthFitScaleNow(for: firstPage))
        let page = try #require(document.page(at: atBottom ? document.pageCount - 1 : 0))
        try await waitForNativeLayout(in: view, page: page)
        if atBottom { view.vimGoToLastPage() } else { view.vimGoToFirstPage() }
        try await waitForNativeLayout(in: view, page: page)
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        let edge = try paperEdgeOrigin(in: view, page: page, atBottom: atBottom)
        let outward: CGFloat = atBottom == documentView.isFlipped ? 1 : -1
        PDFNativeScrollBoundsConstraint.beginLiveScroll(in: scrollView)
        clipView.scroll(to: clipView.constrainBoundsRect(NSRect(
            origin: NSPoint(x: edge.x, y: edge.y + outward * 30), size: clipView.bounds.size
        )).origin)
        scrollView.reflectScrolledClipView(clipView)
        let start = clipView.bounds.origin.y
        let gap = abs(start - edge.y)
        try #require(gap > 1)
        @MainActor final class Samples { var values: [CGFloat] = [] }
        let samples = Samples()
        let observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { _ in
            MainActor.assumeIsolated { samples.values.append(clipView.bounds.origin.y) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        PDFNativeScrollBoundsConstraint.endLiveScroll(in: scrollView)
        try await waitForSettlement(of: clipView, at: edge.y)
        #expect(!samples.values.isEmpty)
        #expect(!samples.values.contains {
            let distance = abs($0 - edge.y)
            return distance > 0.5 && distance < gap - 0.5
        })
    }

    @MainActor
    private func paperEdgeOrigin(in view: VellumPDFView, page: PDFPage, atBottom: Bool) throws -> NSPoint {
        let scrollView = try #require(view.pdfScrollView)
        let documentView = try #require(scrollView.documentView)
        let clipView = scrollView.contentView
        let paper = view.convert(view.convert(page.bounds(for: view.displayBox), from: page), to: documentView)
        let y = atBottom != documentView.isFlipped ? paper.minY : paper.maxY - clipView.bounds.height
        // Native resting positions may be rounded; settlement targets the exact converted paper edge.
        #expect(abs(clipView.bounds.origin.y - y) < 0.5)
        return NSPoint(x: clipView.bounds.origin.x, y: y)
    }

    @MainActor
    private func waitForNativeLayout(in view: VellumPDFView, page: PDFPage) async throws {
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        var previousPaper = view.convert(page.bounds(for: view.displayBox), from: page)
        var previousViewport = clipView.bounds
        var quietSince = ProcessInfo.processInfo.systemUptime
        try await waitForTestCondition("PDFKit finishes native magnification and viewport layout") {
            let paper = view.convert(page.bounds(for: view.displayBox), from: page)
            let viewport = clipView.bounds
            let now = ProcessInfo.processInfo.systemUptime
            if paper != previousPaper || viewport != previousViewport {
                previousPaper = paper
                previousViewport = viewport
                quietSince = now
            }
            return now - quietSince >= 0.04
        }
    }

    @MainActor
    private func sendNativeScroll(
        _ delta: Int32, to scrollView: NSScrollView, phase: CGScrollPhase? = nil,
        momentum: CGMomentumScrollPhase = .none
    ) throws {
        let cgEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0
        ))
        if phase != nil || momentum != .none {
            cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        }
        if let phase {
            cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        }
        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        scrollView.scrollWheel(with: try #require(NSEvent(cgEvent: cgEvent)))
    }

    @MainActor
    private func waitForSettlement(of clipView: NSClipView, at targetY: CGFloat, quietInterval: TimeInterval = 0.08) async throws {
        var lastY = clipView.bounds.origin.y
        var quietSince = ProcessInfo.processInfo.systemUptime
        // A quiet interval also observes deferred writes when the first sample is already at the edge.
        do {
            try await waitForTestCondition("native scrolling settles at the paper edge") {
                let now = ProcessInfo.processInfo.systemUptime
                let currentY = clipView.bounds.origin.y
                if abs(currentY - lastY) > 0.001 {
                    lastY = currentY
                    quietSince = now
                }
                return abs(currentY - targetY) < 0.001 && now - quietSince >= quietInterval
            }
        } catch {
            Issue.record("Native settlement expected y=\(targetY), actual y=\(clipView.bounds.origin.y)")
            throw error
        }
        #expect(abs(clipView.bounds.origin.y - targetY) < 0.001)
    }

    @MainActor
    private func makeReader() throws -> (NSWindow, VellumPDFView, PDFPage) {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 2000, height: 2400), for: .mediaBox)
            page.setBounds(index == 1
                ? NSRect(x: 40, y: 60, width: 1000, height: 1400)
                : NSRect(x: 0, y: 0, width: 2000, height: 2400), for: .cropBox)
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

import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("PDF page fit animation")
struct PDFPageFitAnimationTests {
    @Test(arguments: [0, 90, 180, 270], [(1, false), (3, false), (1, true), (3, true)]) @MainActor
    func bottomAlignedPageFitsBeforeMovingToTop(rotation: Int, configuration: (pageCount: Int, short: Bool)) async throws {
        let (window, view, page) = try makeReader(
            rotation: rotation, pageCount: configuration.pageCount, short: configuration.short
        )
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        let clipView = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        view.vimZoomToFit()
        try await finishZoom(in: view)
        view.vimGoToLastPage()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        try await Task.sleep(for: .milliseconds(30))

        func gaps() -> (top: CGFloat, bottom: CGFloat, height: CGFloat) {
            let paper = view.convert(view.convert(page.bounds(for: view.displayBox), from: page), to: documentView)
            let viewport = clipView.bounds
            return documentView.isFlipped
                ? (paper.minY - viewport.minY, viewport.maxY - paper.maxY, paper.height)
                : (viewport.maxY - paper.maxY, paper.minY - viewport.minY, paper.height)
        }
        #expect(abs(gaps().bottom) < 0.5)
        let startingScale = view.scaleFactor
        view.vimZoomToPageFit()
        #expect(view.animationState.zoomPageFitPhase == .bottom)
        #expect(view.animationState.zoomAnchor?.page === page)
        #expect(abs(gaps().bottom) < 0.5)
        let target = try #require(view.animationState.zoomTargetScale)
        var sawShrinking = false
        var sawAlignment = false
        var previousBottomGap: CGFloat = 0
        for _ in 0..<120 {
            view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepZoomAnimation()
            let frame = gaps()
            if view.scaleFactor > target + 0.001 {
                sawShrinking = true
                #expect(abs(frame.bottom) < 0.5)
            } else if frame.bottom > 0.5 {
                sawAlignment = true
                #expect(abs(view.scaleFactor - target) < 0.001)
                #expect(frame.bottom >= previousBottomGap - 0.5)
                #expect(frame.bottom - previousBottomGap < max(1, (clipView.bounds.height - frame.height) * 0.5))
                previousBottomGap = frame.bottom
            }
            try await Task.sleep(for: .milliseconds(1))
            if view.animationState.zoomPageFitPhase == .bottom, view.scaleFactor > target + 0.001 {
                #expect(abs(gaps().bottom) < 0.5)
            }
            if !view.animationState.hasActiveZoomTimer { break }
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!view.animationState.hasActiveZoomTimer)
        #expect(abs(view.scaleFactor - target) < 0.001)
        #expect(abs(gaps().top) < 0.5)
        #expect(gaps().height <= clipView.bounds.height + 0.5)
        #expect(startingScale <= target + 0.001 || sawShrinking)
        #expect(clipView.bounds.height - gaps().height <= 0.5 || sawAlignment)
    }

    @Test(arguments: [false, true], ["scroll", "page", "zoom", "widthFit", "pageFit", "restore", "dismantle"]) @MainActor
    func newInteractionCancelsEitherPageFitStage(aligningTop: Bool, interaction: String) async throws {
        let (window, view, page) = try makeReader(rotation: aligningTop ? 90 : 0, pageCount: 3)
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        #expect(view.applyWidthFitScaleNow(for: page))
        view.scrollToDocumentEdge(.bottom)
        view.vimZoomToPageFit()
        #expect(view.animationState.zoomPageFitPhase == .bottom)
        view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
        view.stepZoomAnimation()
        if aligningTop {
            #expect(view.animationState.zoomPageFitPhase == .aligningTop)
            view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepZoomAnimation()
        }
        let target = try #require(view.animationState.zoomTargetScale)
        switch interaction {
        case "scroll": view.vimScroll(x: 0, y: 100)
        case "page": view.vimGoToFirstPage()
        case "zoom": view.vimZoom(to: target * 2)
        case "widthFit": view.vimZoomToFit()
        case "pageFit": view.vimZoomToPageFit()
        case "restore": view.restore(nil)
        default: PDFReader.dismantleNSView(view, coordinator: ())
        }
        if interaction == "pageFit" {
            #expect(view.animationState.zoomPageFitPhase == (aligningTop ? .top : .bottom))
        } else {
            #expect(view.animationState.zoomPageFitPhase == nil)
        }
        if ["zoom", "widthFit", "pageFit"].contains(interaction) {
            let nextTarget = try #require(view.animationState.zoomTargetScale)
            try await finishZoom(in: view)
            #expect(abs(view.scaleFactor - nextTarget) < 0.001)
        } else {
            #expect(!view.animationState.hasActiveZoomTimer)
            #expect(view.animationState.zoomTargetScale == nil)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            try await Task.sleep(for: .milliseconds(30))
            let origin = try #require(view.pdfScrollView?.contentView.bounds.origin)
            view.stepZoomAnimation()
            #expect(view.pdfScrollView?.contentView.bounds.origin == origin)
        }
    }

    @Test @MainActor
    func replacingDocumentCancelsPendingTopAlignment() async throws {
        let (window, initialView, _) = try makeReader(rotation: 90, pageCount: 3)
        let document = try #require(initialView.document)
        let defaults = try #require(UserDefaults(suiteName: "PageFitReplacement.\(UUID().uuidString)"))
        let appState = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false
        ))
        let tab = PDFTab(url: URL(fileURLWithPath: "/tmp/page-fit-replacement.pdf"), document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let hostingView = NSHostingView(rootView: PDFReader(
            tabID: tab.id, document: document, snapshot: nil, isActive: true
        ).environmentObject(appState))
        window.contentView = hostingView
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        let view = try #require(appState.activeReaderController as? VellumPDFView)
        defer { view.cancelPendingRestore(); view.stopZoomState(); view.stopScrollAnimation() }
        #expect(view.applyWidthFitScaleNow())
        view.scrollToDocumentEdge(.bottom)
        view.vimZoomToPageFit()
        view.stepZoomAnimation()
        #expect(view.animationState.zoomPageFitPhase == .aligningTop)
        let timer = try #require(view.animationState.zoomTimer)

        let replacement = PDFDocument()
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 900), for: .mediaBox)
        replacement.insert(page, at: 0)
        hostingView.rootView = PDFReader(
            tabID: tab.id, document: replacement, snapshot: nil, isActive: true
        ).environmentObject(appState)
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(view.document === replacement)
        #expect(!timer.isValid)
        #expect(view.animationState.zoomPageFitPhase == nil)
        #expect(view.animationState.zoomTargetScale == nil)
    }

    @MainActor
    private func finishZoom(in view: VellumPDFView) async throws {
        for _ in 0..<120 {
            view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepZoomAnimation()
            try await Task.sleep(for: .milliseconds(1))
            if !view.animationState.hasActiveZoomTimer { break }
        }
        try await Task.sleep(for: .milliseconds(30))
    }

    @MainActor
    private func makeReader(rotation: Int, pageCount: Int, short: Bool = false) throws -> (NSWindow, VellumPDFView, PDFPage) {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 800, height: 1_100), for: .mediaBox)
            page.setBounds(NSRect(x: 40, y: 60, width: 600, height: short ? 100 : 900), for: .cropBox)
            page.rotation = rotation
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
        view.scaleFactor = 1.2
        view.layoutDocumentView()
        return (window, view, try #require(document.page(at: pageCount - 1)))
    }
}

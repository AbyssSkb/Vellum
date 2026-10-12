@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Reader outline position integration")
struct PDFReadingPositionTests {
    @Test(arguments: [0, 90, 180, 270])
    func readingAnchorUsesTheViewportCenterOnCroppedRotatedPages(rotation: Int) throws {
        let fixture = try makeReader(rotation: rotation)
        defer { fixture.cleanup() }
        let destination = try #require(fixture.view.readingDestination())
        #expect(destination.page === fixture.page)
        #expect(abs(destination.point.x - 540) < 1)
        #expect(abs(destination.point.y - 760) < 1)
    }

    @Test
    func wholePageFitRecognizesASectionWhoseHeadingIsBelowThePageMargin() throws {
        let fixture = try makeReader()
        defer { fixture.cleanup() }
        fixture.view.applyZoomScale(try #require(fixture.view.pageFitScale(for: fixture.page)))
        fixture.view.centerBothAxes(on: fixture.view.pageCenterDestination(for: fixture.page))
        let items = PDFOutlineBuilder.items(for: fixture.document)
        let destination = try #require(fixture.view.readingDestination())
        #expect(OutlineReadingMatcher.item(for: destination, in: items) === items.first)
    }

    @Test(arguments: [CGFloat(0.75), 1, 1.5])
    func scrollingSwitchesSectionsAtTheSameHeadingInBothDirections(scale: CGFloat) throws {
        let fixture = try makeReader()
        defer { fixture.cleanup() }
        fixture.view.applyZoomScale(scale)
        let items = PDFOutlineBuilder.items(for: fixture.document)
        for (y, section) in [(CGFloat(700), 0), (660, 0), (640, 1), (660, 0), (700, 0)] {
            fixture.view.centerBothAxes(on: PDFDestination(page: fixture.page, at: NSPoint(x: 540, y: y)))
            let destination = try #require(fixture.view.readingDestination())
            #expect(OutlineReadingMatcher.item(for: destination, in: items) === items[section])
        }
    }

    @Test
    func explicitSamePageSectionSurvivesZoomAndResizeUntilActualScroll() async throws {
        let fixture = try makeReader()
        defer { fixture.cleanup() }
        let target = try #require(PDFOutlineBuilder.items(for: fixture.document).last?.destination)
        fixture.view.scheduleReadingPositionReport(userNavigated: true)
        fixture.appState.jumpToOutlineDestination(target, itemID: "1")
        try await waitForTestCondition("Outline navigation reports the settled viewport") {
            fixture.appState.outlineReadingDestination?.point == fixture.view.readingDestination()?.point
        }
        fixture.view.vimZoom(to: 1.2)
        fixture.view.applyZoomScale(1.2)
        fixture.view.stopZoomState()
        fixture.window.setContentSize(NSSize(width: 820, height: 640))
        fixture.view.layoutDocumentView()
        fixture.view.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()
        #expect(fixture.appState.outlineReadingItemID == "1")
        fixture.view.vimScroll(x: 0, y: -120)
        let scrollView = try #require(fixture.view.pdfScrollView)
        fixture.view.stepScrollAnimation(in: scrollView)
        try await waitForTestCondition("Scrolling releases the pinned outline section") {
            fixture.appState.outlineReadingItemID == nil
        }
    }

    @Test
    func galleryIsTentativeAndCancellationKeepsTheReadingOrigin() async throws {
        let fixture = try makeReader()
        defer { fixture.cleanup() }
        fixture.view.scheduleReadingPositionReport()
        try await waitForTestCondition("The reader reports its initial gallery position") {
            fixture.appState.outlineReadingDestination != nil
        }
        fixture.view.layoutSubtreeIfNeeded()
        var settledSnapshot = fixture.view.snapshot()
        var quietSince = ContinuousClock.now
        // PDFKit can finish positioning after the first reading report.
        try await waitForTestCondition("The native reading position settles before opening the gallery") {
            let current = fixture.view.snapshot()
            if current != settledSnapshot {
                settledSnapshot = current
                quietSince = ContinuousClock.now
            }
            return current != nil && quietSince.duration(to: ContinuousClock.now) >= .milliseconds(30)
        }
        let origin = try #require(settledSnapshot)
        let reportedPage = fixture.appState.outlineReadingDestination?.page
        fixture.appState.outlineReadingItemID = "0"
        #expect(fixture.view.beginPageOverview())
        #expect(fixture.view.movePageOverview(.next))
        fixture.view.scheduleReadingPositionReport()
        await nextTestMainQueueTurn()
        #expect(fixture.appState.outlineReadingDestination?.page === reportedPage)
        fixture.view.cancelPageOverview()
        #expect(fixture.view.snapshot() == origin)
        #expect(fixture.appState.outlineReadingItemID == "0")
        #expect(fixture.view.beginPageOverview())
        #expect(fixture.view.movePageOverview(.next))
        fixture.view.finishPageOverview()
        try await waitForTestCondition("The gallery reports its committed page") {
            fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 2)
                && fixture.appState.outlineReadingItemID == nil
        }
        #expect(fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 2))
        #expect(fixture.appState.outlineReadingItemID == nil)
    }

    @Test
    func internalSamePageLinksPinTheirSectionAndExternalLinksKeepIt() async throws {
        let fixture = try makeReader()
        defer { fixture.cleanup() }
        let target = try #require(PDFOutlineBuilder.items(for: fixture.document).last?.destination)
        let link = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        link.destination = target
        fixture.view.reportInternalLinkNavigation(link, from: fixture.view.readingDestination(), generation: fixture.view.restoreGeneration)
        await nextTestMainQueueTurn()
        #expect(fixture.appState.outlineReadingItemID == "1")
        let external = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        external.action = PDFActionURL(url: URL(string: "https://example.com")!)
        fixture.view.reportInternalLinkNavigation(external, from: fixture.view.readingDestination(), generation: fixture.view.restoreGeneration)
        #expect(fixture.appState.outlineReadingItemID == "1")
        fixture.view.vimPerformPDFAction(PDFActionNamed(name: .lastPage))
        try await waitForTestCondition("The named PDF action reports its destination") {
            fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 2)
                && fixture.appState.outlineReadingItemID == nil
        }
        #expect(fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 2))
        #expect(fixture.appState.outlineReadingItemID == nil)
    }

    @Test
    func settledRestoreReportsTheNewPositionAndOldDocumentsCannotOverrideIt() async throws {
        let fixture = try makeReader()
        defer { fixture.cleanup() }
        fixture.view.restore(.initial)
        try await waitForTestCondition("Restore finishes and reports the new reading position") {
            fixture.view.pendingRestoreAction == nil
                && fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 0)
        }
        #expect(fixture.view.pendingRestoreAction == nil)
        #expect(fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 0))
        let other = PDFDocument()
        other.insert(PDFPage(), at: 0)
        _ = fixture.appState.tabStore.openInNewTabs([PDFTab(url: nil, document: other)])
        let otherPage = try #require(other.page(at: 0))
        fixture.appState.outlineReadingDestination = PDFDestination(page: otherPage, at: .zero)
        fixture.view.scheduleReadingPositionReport(userNavigated: true)
        await nextTestMainQueueTurn()
        #expect(fixture.appState.outlineReadingDestination?.page === otherPage)
    }

    @MainActor
    private struct ReaderFixture {
        let window: NSWindow
        let view: VellumPDFView
        let page: PDFPage
        let document: PDFDocument
        let appState: AppState
        let preferences: TestPreferences

        func cleanup() {
            view.cancelPendingRestore()
            view.cancelPageOverview()
            view.stopScrollAnimation()
            view.stopZoomState()
            view.readerStateSaveWorkItem?.cancel()
            view.readingPositionReportWorkItem?.cancel()
            window.close()
            preferences.cleanup()
        }
    }

    private func makeReader(rotation: Int = 0) throws -> ReaderFixture {
        _ = NSApplication.shared
        let preferences = try TestPreferences()
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 2000, height: 2400), for: .mediaBox)
            page.setBounds(NSRect(x: 40, y: 60, width: 1000, height: 1400), for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: index)
        }
        let page = document.page(at: 1)!
        let outline = PDFOutline()
        for (index, y) in [CGFloat(1360), 650].enumerated() {
            let item = PDFOutline()
            item.label = "Section \(index + 1)"
            item.destination = PDFDestination(page: page, at: NSPoint(x: 500, y: y))
            outline.insertChild(item, at: index)
        }
        document.outlineRoot = outline
        let appState = makeTestAppState(defaults: preferences.defaults)
        let tab = PDFTab(url: nil, document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.displayBox = .cropBox
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        view.centerBothAxes(on: view.pageCenterDestination(for: page))
        view.appState = appState
        appState.readerWindow = window
        appState.activeReaderController = view
        return ReaderFixture(window: window, view: view, page: page, document: document,
                             appState: appState, preferences: preferences)
    }
}

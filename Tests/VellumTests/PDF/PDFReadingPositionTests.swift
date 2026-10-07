@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Reader outline position integration")
struct PDFReadingPositionTests {
    @Test(arguments: [0, 90, 180, 270])
    func readingAnchorUsesTheViewportCenterOnCroppedRotatedPages(rotation: Int) throws {
        let fixture = makeReader(rotation: rotation)
        defer { fixture.window.close() }
        let destination = try #require(fixture.view.readingDestination())
        #expect(destination.page === fixture.page)
        let geometry = PDFPageDisplayGeometry(page: fixture.page, box: .cropBox)
        let point = geometry.point(forPagePoint: destination.point)
        #expect(abs(point.x - geometry.bounds.midX) < 1)
        #expect(abs(point.y - geometry.bounds.midY) < 1)
    }

    @Test
    func wholePageFitRecognizesASectionWhoseHeadingIsBelowThePageMargin() throws {
        let fixture = makeReader()
        defer { fixture.window.close() }
        fixture.view.applyZoomScale(try #require(fixture.view.pageFitScale(for: fixture.page)))
        fixture.view.centerBothAxes(on: fixture.view.pageCenterDestination(for: fixture.page))
        let items = PDFOutlineBuilder.items(for: fixture.document)
        let destination = try #require(fixture.view.readingDestination())
        #expect(OutlineReadingMatcher.item(for: destination, in: items) === items.first)
    }

    @Test(arguments: [CGFloat(0.75), 1, 1.5])
    func scrollingSwitchesSectionsAtTheSameHeadingInBothDirections(scale: CGFloat) throws {
        let fixture = makeReader()
        defer { fixture.window.close() }
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
        let fixture = makeReader()
        defer { fixture.view.stopScrollAnimation(); fixture.view.stopZoomState(); fixture.window.close() }
        let target = try #require(PDFOutlineBuilder.items(for: fixture.document).last?.destination)
        fixture.view.scheduleReadingPositionReport(userNavigated: true)
        fixture.appState.jumpToOutlineDestination(target, itemID: "1")
        try await Task.sleep(for: .milliseconds(30))
        fixture.view.vimZoom(to: 1.2)
        fixture.view.applyZoomScale(1.2)
        fixture.view.stopZoomState()
        fixture.window.setContentSize(NSSize(width: 820, height: 640))
        fixture.view.layoutDocumentView()
        fixture.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.appState.outlineReadingItemID == "1")
        fixture.view.vimScroll(x: 0, y: -120)
        let scrollView = try #require(fixture.view.pdfScrollView)
        fixture.view.stepScrollAnimation(in: scrollView)
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.appState.outlineReadingItemID == nil)
    }

    @Test
    func galleryIsTentativeAndCancellationKeepsTheReadingOrigin() async throws {
        let fixture = makeReader()
        defer { fixture.view.cancelPageOverview(); fixture.window.close() }
        fixture.view.scheduleReadingPositionReport()
        try await Task.sleep(for: .milliseconds(20))
        let origin = try #require(fixture.view.snapshot())
        let reportedPage = fixture.appState.outlineReadingDestination?.page
        fixture.appState.outlineReadingItemID = "0"
        #expect(fixture.view.beginPageOverview())
        #expect(fixture.view.movePageOverview(.next))
        fixture.view.scheduleReadingPositionReport()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.appState.outlineReadingDestination?.page === reportedPage)
        fixture.view.cancelPageOverview()
        #expect(fixture.view.snapshot() == origin)
        #expect(fixture.appState.outlineReadingItemID == "0")
        #expect(fixture.view.beginPageOverview())
        #expect(fixture.view.movePageOverview(.next))
        fixture.view.finishPageOverview()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 2))
        #expect(fixture.appState.outlineReadingItemID == nil)
    }

    @Test
    func internalSamePageLinksPinTheirSectionAndExternalLinksKeepIt() async throws {
        let fixture = makeReader()
        defer { fixture.window.close() }
        let target = try #require(PDFOutlineBuilder.items(for: fixture.document).last?.destination)
        let link = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        link.destination = target
        fixture.view.reportInternalLinkNavigation(link, from: fixture.view.readingDestination(), generation: fixture.view.restoreGeneration)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.appState.outlineReadingItemID == "1")
        let external = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        external.action = PDFActionURL(url: URL(string: "https://example.com")!)
        fixture.view.reportInternalLinkNavigation(external, from: fixture.view.readingDestination(), generation: fixture.view.restoreGeneration)
        #expect(fixture.appState.outlineReadingItemID == "1")
        fixture.view.vimPerformPDFAction(PDFActionNamed(name: .lastPage))
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 2))
        #expect(fixture.appState.outlineReadingItemID == nil)
    }

    @Test
    func settledRestoreReportsTheNewPositionAndOldDocumentsCannotOverrideIt() async throws {
        let fixture = makeReader()
        defer { fixture.window.close() }
        fixture.view.restore(.initial)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.view.pendingRestoreAction == nil)
        #expect(fixture.appState.outlineReadingDestination?.page === fixture.document.page(at: 0))
        let other = PDFDocument()
        other.insert(PDFPage(), at: 0)
        _ = fixture.appState.tabStore.openInNewTabs([PDFTab(url: nil, document: other)])
        let otherPage = try #require(other.page(at: 0))
        fixture.appState.outlineReadingDestination = PDFDestination(page: otherPage, at: .zero)
        fixture.view.scheduleReadingPositionReport(userNavigated: true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.appState.outlineReadingDestination?.page === otherPage)
    }

    private func makeReader(rotation: Int = 0) -> (
        window: NSWindow, view: VellumPDFView, page: PDFPage, document: PDFDocument, appState: AppState
    ) {
        _ = NSApplication.shared
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
        let appState = AppState(sessionDefaults: UserDefaults(suiteName: UUID().uuidString)!, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false
        ))
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
        return (window, view, page, document, appState)
    }
}

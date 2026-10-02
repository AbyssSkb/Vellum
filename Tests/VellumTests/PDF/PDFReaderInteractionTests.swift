import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("PDF reader interactions")
struct PDFReaderInteractionTests {
    @Test
    @MainActor
    func snapshotUpdatePreservesTextInputFocus() throws {
        let (window, reader) = try makeReader()
        defer { window.close() }
        let appState = AppState()
        let document = try #require(reader.document)
        let tab = PDFTab(url: URL(fileURLWithPath: "/tmp/focus-test.pdf"), document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let hostingView = NSHostingView(rootView: PDFReader(
            tabID: tab.id, document: document, snapshot: nil, isActive: true
        ).environmentObject(appState))
        hostingView.frame = window.contentView!.bounds
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let mountedReader = try #require(appState.activeReaderController as? VellumPDFView)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        hostingView.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        let snapshot = try #require(mountedReader.snapshot())

        hostingView.rootView = PDFReader(
            tabID: tab.id, document: document, snapshot: snapshot, isActive: true
        ).environmentObject(appState)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(appState.activeReaderController === mountedReader)
        #expect(window.firstResponder === editor)
    }

    @Test
    @MainActor
    func inactiveReaderAttachmentAndOverviewDismissalPreserveResponder() throws {
        let (window, reader) = try makeReader()
        defer { window.close() }
        let editor = NSTextView()
        reader.addSubview(editor)
        #expect(reader.beginPageOverview())
        #expect(window.makeFirstResponder(editor))
        reader.finishPageOverview()
        #expect(window.firstResponder === editor)

        let appState = AppState()
        reader.appState = appState
        let inactiveReader = VellumPDFView(frame: reader.bounds)
        inactiveReader.appState = reader.appState
        reader.addSubview(inactiveReader)
        #expect(inactiveReader.appState === appState)
        #expect(window.firstResponder === editor)
    }

    @Test
    @MainActor
    func cancellingPageOverviewDiscardsSelectionWithoutNavigationOrFocusChange() throws {
        let (window, reader) = try makeReader()
        defer { window.close() }
        let document = try #require(reader.document)
        let firstPage = try #require(document.page(at: 0))
        let secondPage = PDFPage()
        secondPage.setBounds(firstPage.bounds(for: .mediaBox), for: .mediaBox)
        document.insert(secondPage, at: 1)
        reader.layoutDocumentView()
        reader.centerBothAxes(on: reader.pageCenterDestination(for: firstPage))
        let originalSnapshot = try #require(reader.snapshot())
        let originalBackStack = reader.jumpBackStack
        let editor = NSTextView()
        reader.addSubview(editor)
        #expect(reader.beginPageOverview())
        #expect(reader.movePageOverview(.next))
        #expect(reader.pageOverviewController?.selectedIndex == 1)
        #expect(window.makeFirstResponder(editor))

        reader.cancelPageOverview()

        #expect(!reader.isPageOverviewActive)
        #expect(reader.snapshot() == originalSnapshot)
        #expect(reader.jumpBackStack == originalBackStack)
        #expect(window.firstResponder === editor)
    }

    @Test(arguments: [CGFloat(60), CGFloat(-60)])
    @MainActor
    func vimScrollInterruptsZoomAndKeepsRepeatedMovement(delta: CGFloat) throws {
        let (window, view) = try makeReader()
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        view.vimZoom(to: 2)
        view.stepZoomAnimation()
        let scale = view.scaleFactor
        let origin = scrollView.contentView.bounds.origin
        let zoomTimer = try #require(view.animationState.zoomTimer)

        view.vimScroll(x: 0, y: delta)
        view.vimScroll(x: 0, y: delta)

        #expect(!zoomTimer.isValid)
        #expect(view.animationState.zoomTimer == nil)
        #expect(view.animationState.zoomTargetScale == nil)
        #expect(view.animationState.zoomAnchor == nil)
        let target = try #require(view.animationState.scrollTargetOrigin)
        #expect(abs(target.y - origin.y - 2 * delta) < 0.5)
        #expect(view.animationState.hasActiveScrollTimer)
        for _ in 0..<60 {
            view.stepZoomAnimation()
            view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepScrollAnimation(in: scrollView)
        }

        #expect(view.scaleFactor == scale)
        #expect(abs(scrollView.contentView.bounds.origin.y - target.y) < 0.5)
        #expect(!view.animationState.hasActiveScrollTimer)
    }

    @Test(arguments: [false, true])
    @MainActor
    func scrollWheelCancelsKeyboardAnimation(zooming: Bool) throws {
        let (window, view) = try makeReader()
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let scrollView = try #require(view.pdfScrollView)
        if zooming {
            view.vimZoom(to: 2)
            view.stepZoomAnimation()
        } else {
            view.vimScroll(x: 0, y: 120)
        }
        let timer = try #require(zooming ? view.animationState.zoomTimer : view.animationState.scrollTimer)
        let cgEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: -24, wheel2: 0, wheel3: 0
        ))
        let event = try #require(NSEvent(cgEvent: cgEvent))

        view.scrollWheel(with: event)

        #expect(!timer.isValid)
        #expect(view.animationState.scrollTimer == nil)
        #expect(view.animationState.scrollTargetOrigin == nil)
        #expect(view.animationState.zoomTimer == nil)
        #expect(view.animationState.zoomTargetScale == nil)
        #expect(view.animationState.zoomAnchor == nil)
        let scale = view.scaleFactor
        let origin = scrollView.contentView.bounds.origin
        view.stepZoomAnimation()
        view.stepScrollAnimation(in: scrollView)
        #expect(view.scaleFactor == scale)
        #expect(scrollView.contentView.bounds.origin == origin)
    }

    @Test
    @MainActor
    func textSelectionMovementInterruptsZoomWithoutRestoringItsAnchor() throws {
        let (window, view) = try makeReader()
        defer { view.stopZoomState(); view.stopScrollAnimation(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let selection = try #require(page.selection(for: NSRange(location: 0, length: 5)))
        view.setCurrentSelection(selection, animate: false)
        view.vimZoom(to: 2)
        view.stepZoomAnimation()
        let scale = view.scaleFactor

        #expect(view.handleTextSelectionKey("j", eventType: .keyDown))

        #expect(view.currentSelection?.string != selection.string)
        #expect(view.animationState.zoomTimer == nil)
        #expect(view.animationState.zoomTargetScale == nil)
        #expect(view.animationState.zoomAnchor == nil)
        let scrollView = try #require(view.pdfScrollView)
        let origin = scrollView.contentView.bounds.origin
        view.stepZoomAnimation()
        #expect(view.scaleFactor == scale)
        #expect(scrollView.contentView.bounds.origin == origin)
    }

    @MainActor
    private func makeReader() throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 1_600)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, text) in ["First line of selectable text", "Second line of selectable text"].enumerated() {
            (text as NSString).draw(
                at: NSPoint(x: 72, y: 1_320 - index * 30),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        view.centerBothAxes(on: view.pageCenterDestination(for: try #require(document.page(at: 0))))
        return (window, view)
    }
}

import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Counted PDF text selection")
struct PDFTextSelectionCountTests {
    @Test(arguments: ["w", "b", "j", "k"], [false, true])
    func longCountRevealsEndpointWithoutHorizontalDrift(key: String, fitWidth: Bool) async throws {
        _ = NSApplication.shared
        let lines = (0..<24).map { index in
            ("one two three four five six seven eight", NSPoint(x: 72, y: 720 - index * 24))
        }
        let document = try makeTextPDF(pages: [lines])
        let page = try #require(document.page(at: 0))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        defer {
            view.cancelPendingRestore()
            view.stopZoomState()
            view.stopScrollAnimation()
            window.close()
        }
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        if fitWidth {
            view.vimZoomToFit()
            view.animationState.zoomTimer?.invalidate()
            for _ in 0..<60 {
                view.animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
                view.stepZoomAnimation()
                await nextTestMainQueueTurn()
                if view.animationState.zoomTargetScale == nil { break }
            }
        }
        let backwards = key == "b" || key == "k"
        view.scrollToDocumentEdge(backwards ? .bottom : .top)
        await nextTestMainQueueTurn()
        view.layoutDocumentView()
        let range = backwards
            ? NSRange(location: page.numberOfCharacters - 5, length: 5)
            : NSRange(location: 0, length: 3)
        view.setCurrentSelection(page.selection(for: range), animate: false)
        let clipView = try #require(view.pdfScrollView).contentView
        let origin = clipView.bounds.origin

        let count = key == "j" || key == "k" ? 12 : 100
        #expect(view.handleTextSelectionKey(key, eventType: .keyDown, count: count))

        #expect(abs(clipView.bounds.origin.x - origin.x) < 0.5,
                "\(count)\(key) moved x from \(origin.x) to \(clipView.bounds.origin.x), fitWidth=\(fitWidth)")
        #expect(abs(clipView.bounds.origin.y - origin.y) > 1)
    }

    @Test(arguments: [0, 90, 180, 270])
    func crossPageWordSelectionKeepsMixedSizePagesCentered(rotation: Int) async throws {
        let lines = (0..<12).map { index in
            ("one two three four five six seven eight", NSPoint(x: 72, y: 720 - index * 24))
        }
        let document = try makeTextPDF(pages: [lines, lines, lines])
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            page.rotation = rotation
            if index == 1 {
                page.setBounds(NSRect(x: 0, y: 0, width: 520, height: 792), for: .mediaBox)
                page.setBounds(NSRect(x: 0, y: 0, width: 520, height: 792), for: .cropBox)
            }
        }
        let (window, view) = try await makeReader(document: document, width: 900, scale: 0.8)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        view.setCurrentSelection(page.selection(for: NSRange(location: 0, length: 3)), animate: false)
        let scrollView = try #require(view.pdfScrollView)
        let clip = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        try #require(documentView.bounds.width < clip.bounds.width)
        let originX = clip.bounds.origin.x

        #expect(view.handleTextSelectionKey("w", eventType: .keyDown, count: 200))

        #expect(view.currentSelection?.pages.count == 3)
        #expect(abs(clip.bounds.origin.x - originX) < 0.5)
    }

    @Test
    func zoomedSelectionStillRevealsAHorizontallyOffscreenEndpoint() async throws {
        let document = try makeTextPDF(pages: [[
            ("one two three four five six seven eight", NSPoint(x: 72, y: 720))
        ]])
        let (window, view) = try await makeReader(document: document, width: 400, scale: 2)
        defer { close(window, view) }
        let page = try #require(document.page(at: 0))
        let scrollView = try #require(view.pdfScrollView)
        let clip = scrollView.contentView
        let documentView = try #require(scrollView.documentView)
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y))
        view.setCurrentSelection(page.selection(for: NSRange(location: 0, length: 3)), animate: false)

        #expect(view.handleTextSelectionKey("e", eventType: .keyDown, count: 5))

        let extent = try #require(view.textSelectionNavigationState?.extentOffset)
        let target = view.convert(view.convert(page.characterBounds(at: extent - 1), from: page), to: documentView)
        #expect(clip.bounds.origin.x > 1)
        #expect(target.minX >= clip.bounds.minX && target.maxX <= clip.bounds.maxX)
    }

    @Test
    func wordCountExtendsToTheRequestedWordAndKeyUpDoesNotMove() throws {
        let document = try makeTextPDF(pages: [[("first second third fourth fifth", NSPoint(x: 72, y: 720))]])
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: NSRange(location: 0, length: 5)), animate: false)

        #expect(view.handleTextSelectionKey("w", eventType: .keyDown, count: 3))

        let text = try #require(page.string)
        let expectedEnd = (text as NSString).range(of: "fourth").location
        #expect(view.textSelectionNavigationState?.anchorOffset == 0)
        #expect(view.textSelectionNavigationState?.extentOffset == expectedEnd)
        let selection = view.currentSelection?.string
        #expect(view.handleTextSelectionKey("w", eventType: .keyUp, count: 3))
        #expect(view.currentSelection?.string == selection)
    }

    @Test(arguments: ["h", "l", "b", "w", "e", "j", "k"])
    func countedMotionsMatchSeparatePressesIncludingAnchorCrossing(key: String) throws {
        let document = try makeTextPDF(pages: [[
            ("first second third fourth fifth", NSPoint(x: 72, y: 720)),
            ("sixth seventh eighth ninth tenth", NSPoint(x: 72, y: 690)),
            ("short line", NSPoint(x: 72, y: 660)),
            ("another selectable line", NSPoint(x: 72, y: 630))
        ], [("text on the next page", NSPoint(x: 72, y: 720))]])
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string)
        let range = (text as NSString).range(of: "seventh")
        let counted = VellumPDFView(frame: .zero)
        let separate = VellumPDFView(frame: .zero)
        for view in [counted, separate] {
            view.document = document
            view.setCurrentSelection(page.selection(for: range), animate: false)
        }

        #expect(counted.handleTextSelectionKey(key, eventType: .keyDown, count: 3))
        for _ in 0..<3 {
            #expect(separate.handleTextSelectionKey(key, eventType: .keyDown))
        }

        #expect(counted.currentSelection?.string == separate.currentSelection?.string)
        #expect(counted.textSelectionNavigationState?.anchorOffset == separate.textSelectionNavigationState?.anchorOffset)
        #expect(counted.textSelectionNavigationState?.extentOffset == separate.textSelectionNavigationState?.extentOffset)
        #expect(counted.textSelectionNavigationState?.preferredX == separate.textSelectionNavigationState?.preferredX)
    }

    @Test(arguments: ["l", "w", "e", "j"])
    func oversizedCountStopsAtDocumentBoundary(key: String) throws {
        let document = try makeTextPDF(pages: [[
            ("first second third", NSPoint(x: 72, y: 720)),
            ("last line", NSPoint(x: 72, y: 690))
        ]])
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: NSRange(location: 0, length: 5)), animate: false)

        #expect(view.handleTextSelectionKey(key, eventType: .keyDown, count: Int.max))
        let boundary = try #require(view.textSelectionNavigationState)
        let selection = view.currentSelection?.string
        #expect(boundary.extentOffset > 5)
        #expect(view.handleTextSelectionKey(key, eventType: .keyDown, count: Int.max))
        #expect(view.textSelectionNavigationState?.extentOffset == boundary.extentOffset)
        #expect(view.currentSelection?.string == selection)
    }

    private func makeReader(document: PDFDocument, width: CGFloat, scale: CGFloat) async throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = scale
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        await nextTestMainQueueTurn()
        return (window, view)
    }

    private func close(_ window: NSWindow, _ view: VellumPDFView) {
        view.cancelPendingRestore()
        view.stopZoomState()
        view.stopScrollAnimation()
        window.close()
    }
}

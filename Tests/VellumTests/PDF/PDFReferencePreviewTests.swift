@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reference preview")
struct PDFReferencePreviewTests {
    @Test
    func choosingAnInternalPreviewPreservesTheReaderAndEscapePreservesItsSelection() async throws {
        let document = try makeTextPDF(pages: [
            [("source text", NSPoint(x: 72, y: 650))],
            [("referenced formula", NSPoint(x: 72, y: 400))]
        ])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let page = try #require(document.page(at: 0))
        let destinationPage = try #require(document.page(at: 1))
        let destination = PDFDestination(page: destinationPage, at: NSPoint(x: 300, y: 400))
        let valid = addLink(on: page, y: 650, destination: destination)
        let action = addLink(on: page, y: 620)
        action.action = PDFActionGoTo(destination: destination)
        let external = addLink(on: page, y: 590)
        external.url = URL(string: "https://example.com/reference")
        _ = addLink(on: page, y: 560)
        let otherDocument = try makeTextPDF(pages: [[]])
        _ = addLink(on: page, y: 530, destination: PDFDestination(
            page: try #require(otherDocument.page(at: 0)), at: .zero))
        let detachedPage = PDFPage()
        _ = addLink(on: page, y: 500, destination: PDFDestination(page: detachedPage, at: .zero))
        reader.setCurrentSelection(try #require(page.selection(for: NSRange(location: 0, length: 6))), animate: false)
        let before = try #require(reader.snapshot())

        reader.beginLinkPreviewCommand()
        let controller = try #require(reader.wordJumpController)
        #expect(controller.targets.count == 2)
        #expect(controller.targets.allSatisfy { $0.link === valid || $0.link === action })
        try chooseFirstPreview(in: reader)
        let panel = try #require(reader.referenceController?.preview)
        #expect(panel.content.sourcePage === destinationPage)
        #expect(panel.content.displayPage !== destinationPage)
        #expect(reader.snapshot() == before)
        #expect(reader.currentSelection?.string == "source")
        #expect(reader.jumpBackStack.isEmpty)
        let clip = try #require(panel.scrollView).contentView
        let initialOrigin = clip.bounds.origin

        #expect(reader.handleReferencePreviewKey(try key("j", in: fixture.window)))
        #expect(abs(clip.bounds.origin.y - initialOrigin.y) > 1)
        #expect(reader.snapshot() == before)
        #expect(reader.handleReferencePreviewKey(try key("k", in: fixture.window)))
        let restoredOrigin = clip.convert(clip.bounds.origin, to: panel.pdfView)
        let expectedOrigin = clip.convert(initialOrigin, to: panel.pdfView)
        // PDFKit aligns scrolling to backing pixels in the scaled clip view.
        #expect(abs(restoredOrigin.y - expectedOrigin.y) <= 1 / fixture.window.backingScaleFactor + 0.001)
        #expect(reader.handleReferencePreviewKey(try key("\u{1b}", in: fixture.window)))

        #expect(reader.referenceController?.preview == nil)
        #expect(reader.currentSelection?.string == "source")
        #expect(reader.snapshot() == before)
        #expect(reader.jumpBackStack.isEmpty)
        #expect(fixture.window.firstResponder === reader)
    }

    @Test(arguments: ["p", "\r"])
    func followingTheReferenceRecordsItsOriginalReadingPosition(key: String) async throws {
        let document = try makeTextPDF(pages: [
            [("source text", NSPoint(x: 72, y: 650))], [], []
        ])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let source = try #require(document.page(at: 0))
        let target = try #require(document.page(at: 2))
        _ = addLink(on: source, y: 650, destination: PDFDestination(page: target, at: NSPoint(x: 72, y: 700)))
        reader.setCurrentSelection(try #require(source.selection(for: NSRange(location: 0, length: 6))), animate: false)
        let before = try #require(reader.snapshot())
        reader.beginLinkPreviewCommand()
        try chooseFirstPreview(in: reader)

        #expect(reader.handleReferencePreviewKey(try self.key(key, in: fixture.window)))

        #expect(reader.referenceController?.preview == nil)
        #expect(reader.currentSelection == nil)
        #expect(reader.jumpBackStack == [before])
        #expect(fixture.window.firstResponder === reader)
        try await waitForTestCondition("Following a preview reaches the linked page") { reader.currentPage === target }
        reader.vimJumpBack()
        try await waitForTestCondition("The reference jump returns to its source") {
            guard let restored = reader.snapshot() else { return false }
            return reader.isSameJumpLocation(restored, before)
        }
    }

    @Test
    func pressingPOnACombinedPreviewNavigatesToTheOriginalPDFDestination() async throws {
        let document = try makeTextPDF(pages: [[], [], []])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let target = try #require(document.page(at: 1))
        let continuation = try #require(document.page(at: 2))
        let destination = PDFDestination(page: target, at: NSPoint(x: 100, y: 430))
        let content = try #require(PDFReferenceContent(document: document, destination: destination,
            crop: NSRect(x: 72, y: 350, width: 460, height: 100), fitsEntireCrop: true,
            continuation: (continuation, NSRect(x: 72, y: 600, width: 460, height: 100))))
        let controller = PDFReferenceController(reader: reader)
        reader.referenceController = controller
        let before = try #require(reader.snapshot())
        controller.show(content, sourceRect: nil)
        #expect(content.displayPage !== target)

        #expect(reader.handleReferencePreviewKey(try key("p", in: fixture.window)))

        #expect(controller.preview == nil)
        #expect(reader.jumpBackStack == [before])
        #expect(content.destination.page === target)
        #expect(content.destination.point == destination.point)
        try await waitForTestCondition("Following a combined preview reaches its original page") { reader.currentPage === target }
        #expect(fixture.window.firstResponder === reader)
    }

    @Test
    func uppercasePLeavesTheFloatingPreviewAndReaderPositionUntouched() async throws {
        let document = try makeTextPDF(pages: [[], []])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let link = addLink(on: try #require(document.page(at: 0)), y: 650,
            destination: PDFDestination(page: try #require(document.page(at: 1)), at: NSPoint(x: 100, y: 430)))
        let before = try #require(reader.snapshot())
        reader.showLinkPreview(for: link)
        let preview = try #require(reader.referenceController?.preview)

        #expect(reader.handleReferencePreviewKey(try key("P", in: fixture.window, modifiers: .shift)))

        #expect(reader.referenceController?.preview === preview)
        #expect(preview.superview === reader)
        #expect(reader.frame == fixture.container.bounds)
        #expect(reader.snapshot() == before)
        #expect(reader.jumpBackStack.isEmpty)
    }

    @Test(arguments: ["table", "equation", "section"])
    func isolatedReferenceRegionsRemainFittedAndCopied(kind: String) async throws {
        let document = try makeTextPDF(pages: [[], [("Referenced content", NSPoint(x: 120, y: 350))]])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let page = try #require(document.page(at: 1))
        let originalCrop = page.bounds(for: .cropBox)
        let crop = NSRect(x: 100, y: 250, width: 400, height: 180)
        let title: AppText
        switch kind {
        case "table": title = .tablePreview("2")
        case "equation": title = .equationPreview("2")
        default: title = .sectionPreview("2")
        }
        let content = try #require(PDFReferenceContent(document: document,
            destination: PDFDestination(page: page, at: NSPoint(x: 72, y: 700)),
            crop: crop, fitsEntireCrop: true, title: title))
        let controller = PDFReferenceController(reader: reader)
        reader.referenceController = controller
        controller.show(content, sourceRect: nil)
        let panel = try #require(controller.preview)

        fixture.container.layoutSubtreeIfNeeded()
        panel.layoutSubtreeIfNeeded()
        #expect(panel.pdfView.frame == panel.bounds.insetBy(dx: 4, dy: 4))
        #expect(panel.layer?.cornerRadius == 10)
        #expect(panel.pdfView.layer?.cornerRadius == 6)
        let clip = try #require(panel.scrollView).contentView
        let paper = panel.pdfView.convert(crop, from: content.displayPage)
        let viewport = panel.pdfView.convert(clip.bounds, from: clip)
        #expect(paper.minX >= viewport.minX - 0.5 && paper.maxX <= viewport.maxX + 0.5)
        #expect(paper.minY >= viewport.minY - 0.5 && paper.maxY <= viewport.maxY + 0.5)
        #expect(abs(paper.midX - viewport.midX) < 0.5)
        #expect(abs(paper.midY - viewport.midY) < 0.5)
        #expect(content.displayPage.bounds(for: .cropBox) == crop)
        #expect(content.displayPage !== page)
        #expect(page.bounds(for: .cropBox) == originalCrop)
        #expect(panel.accessibilityLabel()?.contains(AppUILanguage.saved().text(title)) == true)
    }

    @Test(arguments: ["landscape", "portrait", "slender", "pageContext"])
    func anOpenPreviewTracksTheReaderWindowSize(kind: String) async throws {
        let document = try makeTextPDF(pages: [[], []])
        let fixture = try await makeReader(document: document, width: 600)
        defer { fixture.close() }
        let reader = fixture.reader
        let page = try #require(document.page(at: 1))
        let crop: NSRect?
        switch kind {
        case "landscape": crop = NSRect(x: 50, y: 100, width: 500, height: 220)
        case "portrait": crop = NSRect(x: 100, y: 100, width: 220, height: 500)
        case "slender": crop = NSRect(x: 100, y: 100, width: 30, height: 500)
        default: crop = nil
        }
        let content = try #require(PDFReferenceContent(document: document,
            destination: PDFDestination(page: page, at: NSPoint(x: 120, y: 350)),
            crop: crop, fitsEntireCrop: crop != nil))
        let controller = PDFReferenceController(reader: reader)
        reader.referenceController = controller
        let sourcePosition = try #require(reader.snapshot())
        controller.show(content, sourceRect: NSRect(x: 580, y: 590, width: 18, height: 18))
        let panel = try #require(controller.preview)
        #expect(reader.snapshot() == sourcePosition)
        var previousSize: NSSize?

        for size in [NSSize(width: 600, height: 480), NSSize(width: 1200, height: 900),
                     NSSize(width: 2200, height: 1300), NSSize(width: 380, height: 300)] {
            fixture.window.setContentSize(size)
            fixture.container.layoutSubtreeIfNeeded()
            reader.layoutSubtreeIfNeeded()
            await nextTestMainQueueTurn()
            let viewport = reader.wordJumpViewport.insetBy(dx: 12, dy: 12)
            #expect(controller.preview === panel)
            #expect(abs(reader.bounds.width - size.width) < 0.5)
            #expect(panel.frame.minX >= viewport.minX - 0.5 && panel.frame.maxX <= viewport.maxX + 0.5)
            #expect(panel.frame.minY >= viewport.minY - 0.5 && panel.frame.maxY <= viewport.maxY + 0.5)
            #expect(panel.frame.width <= viewport.width * 0.6 + 0.5)
            #expect(panel.frame.height <= viewport.height * 0.6 + 0.5)
            #expect(abs(panel.frame.width - viewport.width * 0.6) < 0.5
                || abs(panel.frame.height - viewport.height * 0.6) < 0.5)
            #expect(panel.pdfView.frame == panel.bounds.insetBy(dx: 4, dy: 4))
            if size.width > 600, let previousSize {
                #expect(panel.frame.width > previousSize.width + 1)
                #expect(panel.frame.height > previousSize.height + 1)
            }
            if crop != nil {
                let geometry = PDFPageDisplayGeometry(page: content.displayPage, box: .cropBox).bounds
                #expect(abs(panel.pdfView.bounds.width / panel.pdfView.bounds.height - geometry.width / geometry.height) < 0.001)
            }
            previousSize = panel.frame.size
        }
    }

    @Test
    func referenceZoomAndPanLeaveTheReaderPositionUntouched() async throws {
        let document = try makeTextPDF(pages: [
            [("source text", NSPoint(x: 72, y: 650))],
            [("referenced formula", NSPoint(x: 72, y: 400))]
        ])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        _ = addLink(on: try #require(document.page(at: 0)), y: 650,
                    destination: PDFDestination(page: try #require(document.page(at: 1)), at: NSPoint(x: 300, y: 400)))
        let beforePreview = try #require(reader.snapshot())
        reader.beginLinkPreviewCommand()
        try chooseFirstPreview(in: reader)
        let controller = try #require(reader.referenceController)
        let panel = try #require(controller.preview)
        let initialScale = panel.pdfView.scaleFactor

        #expect(reader.handleReferencePreviewKey(try key("=", in: fixture.window)))
        #expect(reader.handleReferencePreviewKey(try key("+", in: fixture.window)))
        #expect(panel.pdfView.scaleFactor > initialScale * 1.3)
        let clip = try #require(panel.scrollView).contentView
        let panOrigin = clip.bounds.origin
        #expect(reader.handleReferencePreviewKey(try key("l", in: fixture.window)))
        #expect(clip.bounds.origin.x - panOrigin.x > 1)
        #expect(reader.handleReferencePreviewKey(try key("h", in: fixture.window)))
        #expect(abs(clip.bounds.origin.x - panOrigin.x) < 0.5)
        #expect(reader.snapshot() == beforePreview)
        let beforeScroll = clip.bounds.origin
        #expect(reader.handleReferencePreviewKey(try key("j", in: fixture.window)))
        #expect(abs(clip.bounds.origin.y - beforeScroll.y) > 1)
        #expect(reader.snapshot() == beforePreview)
        #expect(reader.handleReferencePreviewKey(try key("x", in: fixture.window)))
        #expect(controller.preview == nil)
        #expect(!reader.handleReferencePreviewKey(try key("j", in: fixture.window)))
        #expect(fixture.window.firstResponder === reader)
    }

    @Test
    func xClosesOnlyTheFocusedReferenceAndLeavesTheMainTabCommandAvailable() async throws {
        let document = try makeTextPDF(pages: [[], []])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let link = addLink(on: try #require(document.page(at: 0)), y: 650,
                           destination: PDFDestination(page: try #require(document.page(at: 1)), at: NSPoint(x: 300, y: 400)))
        reader.showLinkPreview(for: link)
        let controller = try #require(reader.referenceController)
        #expect(reader.handleReferencePreviewKey(try key("x", in: fixture.window)))
        #expect(controller.preview == nil)
        #expect(!reader.handleReferencePreviewKey(try key("x", in: fixture.window)))
        #expect(reader.document === document)
        #expect(fixture.window.firstResponder === reader)
    }

    @Test
    func replacingTheDocumentClearsThePreview() async throws {
        let document = try makeTextPDF(pages: [[], []])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let link = addLink(on: try #require(document.page(at: 0)), y: 650,
                           destination: PDFDestination(page: try #require(document.page(at: 1)), at: NSPoint(x: 72, y: 650)))
        reader.showLinkPreview(for: link)
        try #require(reader.referenceController?.preview != nil)

        reader.document = try makeTextPDF(pages: [[]])
        await nextTestMainQueueTurn()

        #expect(reader.referenceController == nil)
    }

    @Test
    func aHintWhoseDestinationMovedToAnotherDocumentCannotOpenOrNavigate() async throws {
        let document = try makeTextPDF(pages: [[], [], []])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let source = try #require(document.page(at: 0))
        let target = try #require(document.page(at: 1))
        _ = addLink(on: source, y: 650, destination: PDFDestination(page: target, at: NSPoint(x: 72, y: 650)))
        reader.beginLinkPreviewCommand()
        let label = try #require(reader.wordJumpController?.session.matches.first).label
        document.removePage(at: 1)
        let replacement = PDFDocument()
        replacement.insert(target, at: 0)

        for character in label { _ = reader.handleWordJumpKey(try key(String(character), in: fixture.window)) }

        #expect(!reader.isWordJumpActive)
        #expect(reader.referenceController?.preview == nil)
        #expect(reader.jumpBackStack.isEmpty)
        #expect(reader.currentPage === source)
    }

    @Test
    func anUnresolvedFigureKeepsTargetPageContextAndReaderPosition() async throws {
        let document = try makeTextPDF(pages: [
            [("Figure 1 shows the architecture.", NSPoint(x: 72, y: 650))],
            [("Figure 1: No independent graphic boundary.", NSPoint(x: 72, y: 400))]
        ])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let reader = fixture.reader
        let target = try #require(document.page(at: 1))
        _ = addLink(on: try #require(document.page(at: 0)), y: 650,
                    destination: PDFDestination(page: target, at: NSPoint(x: 72, y: 650)))
        let before = try #require(reader.snapshot())

        reader.beginLinkPreviewCommand()
        let label = try #require(reader.wordJumpController?.session.matches.first).label
        for character in label { #expect(reader.handleWordJumpKey(try key(String(character), in: fixture.window))) }

        #expect(!reader.isWordJumpActive)
        let panel = try #require(reader.referenceController?.preview)
        #expect(panel.content.sourcePage === target)
        #expect(!panel.content.fitsEntireCrop)
        #expect(panel.content.displayPage.bounds(for: .cropBox) == target.bounds(for: .cropBox))
        #expect(reader.snapshot() == before)
        #expect(reader.handleReferencePreviewKey(try key("j", in: fixture.window)))
        #expect(reader.handleReferencePreviewKey(try key("x", in: fixture.window)))
        #expect(reader.referenceController?.preview == nil)
        #expect(!reader.handleReferencePreviewKey(try key("j", in: fixture.window)))
    }

    @Test
    func pagesWithoutPreviewableLinksDoNotCaptureKeyboardInput() async throws {
        let document = try makeTextPDF(pages: [[]])
        let fixture = try await makeReader(document: document)
        defer { fixture.close() }
        let link = addLink(on: try #require(document.page(at: 0)), y: 650)
        link.url = URL(string: "https://example.com/reference")

        fixture.reader.beginLinkPreviewCommand()

        #expect(!fixture.reader.isWordJumpActive)
        #expect(fixture.reader.referenceController?.preview == nil)
        #expect(!fixture.reader.handleWordJumpKey(try key("j", in: fixture.window)))
        #expect(!fixture.reader.handleReferencePreviewKey(try key("j", in: fixture.window)))
    }

    private func addLink(on page: PDFPage, y: CGFloat, destination: PDFDestination? = nil) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: NSRect(x: 72, y: y, width: 80, height: 18), forType: .link, withProperties: nil)
        annotation.destination = destination
        page.addAnnotation(annotation)
        return annotation
    }

    private func chooseFirstPreview(in reader: VellumPDFView) throws {
        let label = try #require(reader.wordJumpController?.session.matches.first).label
        for character in label { #expect(reader.handleWordJumpKey(try key(String(character), in: #require(reader.window)))) }
        try #require(reader.referenceController?.preview != nil)
        reader.referenceController?.layoutPreview()
    }

    private func key(_ key: String, in window: NSWindow, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
    }

    private func makeReader(document: PDFDocument, width: CGFloat = 1000) async throws -> Fixture {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: width, height: 620)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let reader = VellumPDFView(frame: frame)
        let container = PDFReaderContainer(reader: reader)
        window.contentView = container
        container.frame = frame
        container.layoutSubtreeIfNeeded()
        reader.displayMode = .singlePageContinuous
        reader.displayBox = .cropBox
        reader.document = document
        reader.autoScales = false
        reader.scaleFactor = 1
        reader.layoutSubtreeIfNeeded()
        reader.layoutDocumentView()
        reader.scrollToDocumentEdge(.top)
        await nextTestMainQueueTurn()
        let fixture = Fixture(window: window, reader: reader, container: container)
        do {
            let firstPage = try #require(document.page(at: 0))
            try await waitForTestCondition("The initial reference reader has visible PDF content") {
                reader.currentPage === firstPage && reader.visiblePages.contains { $0 === firstPage }
            }
            try #require(window.makeFirstResponder(reader))
        } catch {
            fixture.close()
            throw error
        }
        return fixture
    }

    @MainActor
    private struct Fixture {
        let window: NSWindow
        let reader: VellumPDFView
        let container: PDFReaderContainer

        func close() {
            reader.clearPDFReferences()
            reader.cancelWordJump()
            reader.searchController?.clear()
            reader.cancelPendingRestore()
            reader.stopScrollAnimation()
            reader.stopZoomState()
            reader.readingPositionReportWorkItem?.cancel()
            reader.readerStateSaveWorkItem?.cancel()
            window.contentView = nil
            window.close()
        }
    }
}

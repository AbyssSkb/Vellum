@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF search focus")
struct PDFSearchFocusTests {
    @Test(arguments: [false, true])
    func longResultCountsHaveRoomBesideTheProgressIndicator(mini: Bool) throws {
        _ = NSApplication.shared
        let overlay = SearchCommandOverlayView(query: "alpha")
        overlay.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        if mini { overlay.showMini(query: "alpha") }
        let surface = try #require(overlay.subviews.first as? NSVisualEffectView)
        let input = try #require(surface.subviews.first { $0.identifier?.rawValue == "pdf-search-input" })
        let status = try #require(surface.subviews.first { $0.identifier?.rawValue == "pdf-search-status" } as? NSTextField)
        let progress = try #require(surface.subviews.first { $0.identifier?.rawValue == "pdf-search-progress" })

        overlay.layoutSubtreeIfNeeded()
        let initialInputFrame = input.frame
        for state in [SearchCommandOverlayView.Status.searching(current: nil, total: 0),
                      .searching(current: 1, total: 2), .count(current: 1, total: 2), .hint("")] {
            overlay.update(status: state)
            overlay.layoutSubtreeIfNeeded()
            #expect(input.frame == initialInputFrame)
        }

        for pending in [true, false] {
            overlay.update(status: pending ? .searching(current: 100000, total: 1000000) : .count(current: 100000, total: 1000000))
            overlay.layoutSubtreeIfNeeded()
            let measuredTextWidth = ceil(status.stringValue.size(withAttributes: [.font: try #require(status.font)]).width)
            #expect(status.frame.width >= measuredTextWidth + 4)
            #expect(progress.isHidden == !pending)
            #expect(!pending || progress.frame.maxX < status.frame.minX)
            #expect(input.frame.maxX < (pending ? progress.frame.minX : status.frame.minX))
            #expect(surface.bounds.contains(status.frame))
            #expect(surface.frame.width <= (mini ? 360 : 520))
        }
    }

    @Test
    func searchUsesOneSurfaceAndKeepsTheInputStableAcrossStatuses() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let field = try fixture.begin()
        let surface = try #require(field.superview as? NSVisualEffectView)
        let status = try #require(surface.subviews.first { $0.identifier?.rawValue == "pdf-search-status" } as? NSTextField)
        let progress = try #require(surface.subviews.first { $0.identifier?.rawValue == "pdf-search-progress" } as? NSProgressIndicator)
        fixture.reader.layoutSubtreeIfNeeded()
        let inputFrame = field.frame
        #expect(surface.subviews.allSatisfy { !($0 is NSVisualEffectView) })
        #expect(surface.frame.width <= 520)
        #expect(status.stringValue.isEmpty)
        #expect(progress.isHidden)

        let controller = try #require(fixture.reader.searchController)
        for query in ["alpha", "missing"] {
            field.stringValue = query
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            fixture.reader.layoutSubtreeIfNeeded()
            #expect(!progress.isHidden)
            #expect(field.frame == inputFrame)
            try await waitForTestCondition("Search status is complete") { !controller.isSearchPending }
            fixture.reader.layoutSubtreeIfNeeded()
            #expect(progress.isHidden)
            #expect(field.frame == inputFrame)
            #expect(status.stringValue == (query == "alpha" ? "1 / 1" : AppUILanguage.saved().text(.searchNoMatch)))
            #expect(status.textColor == (query == "alpha" ? VellumColors.muted : NSColor.systemOrange))
        }
    }

    @Test
    func committedSearchReusesTheSurfaceAndStopsInterceptingItsExpandedArea() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let field = try fixture.begin()
        let surface = try #require(field.superview as? NSVisualEffectView)
        let overlay = try #require(surface.superview)
        let controller = try #require(fixture.reader.searchController)
        field.stringValue = "alpha"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await waitForTestCondition("Search finds its result") { !controller.isSearchPending }
        fixture.reader.layoutSubtreeIfNeeded()
        let expandedEdge = NSPoint(x: surface.frame.minX + 2, y: surface.frame.midY)

        #expect(field.delegate?.control?(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        fixture.reader.layoutSubtreeIfNeeded()

        let query = try #require(surface.subviews.first { $0.identifier?.rawValue == "pdf-search-query" } as? NSTextField)
        #expect(surface.superview === overlay)
        #expect(field.isHidden)
        #expect(!query.isHidden && query.stringValue == "alpha")
        #expect(surface.frame.width < 360)
        #expect(overlay.hitTest(expandedEdge) == nil)
    }

    @Test(arguments: [false, true])
    func noMatchCommitKeepsTheQueryEditable(previewComplete: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try #require(fixture.window.makeFirstResponder(fixture.outline))
        let field = try fixture.begin()
        let editor = try await fixture.focusedEditor(for: field)
        field.stringValue = "missing"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        let controller = try #require(fixture.reader.searchController)
        if previewComplete {
            try await waitForTestCondition("Preview completes without matching text") { !controller.isSearchPending }
        }

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)

        try await waitForTestCondition("Committed search completes without matching text") { !controller.isSearchPending }
        #expect(fixture.window.firstResponder === editor)
        #expect(!field.isHiddenOrHasHiddenAncestor)
        #expect(!controller.hasVisibleHighlights)
    }

    @Test
    func unicodeCaretUsesUTF16AndIMEKeepsEnterAndEscape() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try #require(fixture.window.makeFirstResponder(fixture.outline))
        let field = try fixture.begin()
        field.stringValue = "🧭e\u{301}标题"
        let editor = try await fixture.focusedEditor(for: field)
        #expect(editor.selectedRange == NSRange(location: field.stringValue.utf16.count, length: 0))

        editor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        try #require(editor.hasMarkedText())
        for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            #expect(field.delegate?.control?(field, textView: editor, doCommandBy: selector) == false)
            #expect(fixture.window.firstResponder === editor)
        }
        editor.unmarkText()
        #expect(try #require(fixture.reader.searchController).handleEscape())
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test
    func committingAndReopeningSearchRestoreTheOutlinePane() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try #require(fixture.window.makeFirstResponder(fixture.outline))
        let field = try fixture.begin()
        let editor = try await fixture.focusedEditor(for: field)
        field.stringValue = "alpha"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        let controller = try #require(fixture.reader.searchController)
        try await waitForTestCondition("Committed search returns focus to outline") {
            controller.hasVisibleHighlights && fixture.window.firstResponder === fixture.outline
        }

        let reopened = try fixture.begin()
        _ = try await fixture.focusedEditor(for: reopened)
        #expect(controller.handleEscape())
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test
    func removedReturnPaneFallsBackToReader() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try #require(fixture.window.makeFirstResponder(fixture.outline))
        _ = try await fixture.focusedEditor(for: fixture.begin())
        fixture.outline.removeFromSuperview()
        #expect(try #require(fixture.reader.searchController).handleEscape())
        #expect(fixture.window.firstResponder === fixture.reader)
    }

    @Test
    func newerFocusRequestSurvivesSearchDismissal() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try #require(fixture.window.makeFirstResponder(fixture.outline))
        _ = try await fixture.focusedEditor(for: fixture.begin())
        let otherEditor = NSTextView(frame: .zero)
        fixture.container.addSubview(otherEditor)
        try #require(fixture.window.makeFirstResponder(otherEditor))
        #expect(try #require(fixture.reader.searchController).handleEscape())
        #expect(fixture.window.firstResponder === otherEditor)
    }

    @Test
    func clearingSearchCancelsItsQueuedFocusRequest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let otherEditor = NSTextView(frame: .zero)
        fixture.container.addSubview(otherEditor)
        try #require(fixture.window.makeFirstResponder(otherEditor))
        _ = try fixture.begin()
        try #require(fixture.reader.searchController).clear()
        await nextTestMainQueueTurn()
        #expect(fixture.window.firstResponder === otherEditor)
    }

    @MainActor
    private struct Fixture {
        let window: NSWindow
        let container: NSView
        let reader: VellumPDFView
        let outline: PDFOutlineKeyView

        init() throws {
            _ = NSApplication.shared
            let data = NSMutableData()
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ("alpha" as NSString).draw(at: NSPoint(x: 72, y: 720), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
            context.closePDF()

            let document = try #require(PDFDocument(data: data as Data))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            container = try #require(window.contentView)
            reader = VellumPDFView(frame: NSRect(x: 200, y: 0, width: 700, height: 600))
            reader.document = document
            outline = PDFOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
            container.addSubview(reader)
            container.addSubview(outline)
        }

        func begin() throws -> NSTextField {
            reader.beginSearchCommand()
            return try #require(fields(in: reader).first { $0.isEditable })
        }

        func focusedEditor(for field: NSTextField) async throws -> NSTextView {
            try await waitForTestCondition("Search field editor receives focus") {
                guard let editor = field.currentEditor() else { return false }
                return window.firstResponder === editor
            }
            return try #require(field.currentEditor() as? NSTextView)
        }

        func cleanUp() {
            reader.searchController?.clear()
            reader.stopScrollAnimation()
            reader.stopZoomState()
            window.close()
        }

        private func fields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
    }
}

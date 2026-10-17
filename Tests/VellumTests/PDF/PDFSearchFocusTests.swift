@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF search focus")
struct PDFSearchFocusTests {
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

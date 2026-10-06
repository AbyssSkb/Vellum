@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF search focus")
struct PDFSearchFocusTests {
    @Test
    func searchRestoresItsPaneAndKeepsNewerFocusRequests() async throws {
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

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = try #require(window.contentView)
        let reader = VellumPDFView(frame: NSRect(x: 200, y: 0, width: 700, height: 600))
        let document = try #require(PDFDocument(data: data as Data))
        reader.document = document
        let outline = PDFOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
        container.addSubview(reader)
        container.addSubview(outline)
        func fields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        func begin() throws -> NSTextField {
            reader.beginSearchCommand()
            return try #require(fields(in: reader).first { $0.isEditable })
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(50)) }
        func expectFocus(_ responder: NSResponder) {
            let hasExpectedFocus = window.firstResponder === responder
            #expect(hasExpectedFocus)
        }

        #expect(window.makeFirstResponder(outline))
        let unicodeField = try begin()
        unicodeField.stringValue = "🧭e\u{301}标题"
        try await settle()
        let unicodeEditor = try #require(unicodeField.currentEditor())
        expectFocus(unicodeEditor)
        #expect(unicodeEditor.selectedRange == NSRange(location: unicodeField.stringValue.utf16.count, length: 0))
        let controller = try #require(reader.searchController)
        defer { controller.clear() }
        if let markedEditor = unicodeEditor as? NSTextView {
            markedEditor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
                #expect(unicodeField.delegate?.control?(unicodeField, textView: markedEditor, doCommandBy: selector) == false)
                expectFocus(markedEditor)
            }
            markedEditor.unmarkText()
        }
        #expect(controller.handleEscape())
        expectFocus(outline)

        let field = try begin()
        try await settle()
        field.stringValue = "alpha"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        try await settle()
        #expect(controller.hasVisibleHighlights)
        expectFocus(outline)

        _ = try begin()
        try await settle()
        #expect(controller.handleEscape())
        expectFocus(outline)

        _ = try begin()
        try await settle()
        outline.removeFromSuperview()
        #expect(controller.handleEscape())
        expectFocus(reader)

        let otherEditor = NSTextView(frame: .zero)
        container.addSubview(otherEditor)
        _ = try begin()
        try await settle()
        #expect(window.makeFirstResponder(otherEditor))
        #expect(controller.handleEscape())
        expectFocus(otherEditor)

        _ = try begin()
        controller.clear()
        try await settle()
        expectFocus(otherEditor)
    }
}

import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Counted PDF text selection")
struct PDFTextSelectionCountTests {
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
}

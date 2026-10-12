import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF text selection cache")
struct PDFTextSelectionCacheTests {
    @Test
    @MainActor
    func repeatedCharacterNavigationDoesNotRescanOtherPages() throws {
        let document = try makeTextPDF(pages: [[
            ("first second third fourth fifth", NSPoint(x: 72, y: 720))
        ]])
        let page = try #require(document.page(at: 0))
        let otherPages = (0..<300).map { _ in CountingTextPage(text: "") }
        for extra in otherPages { document.insert(extra, at: document.pageCount) }
        let view = VellumPDFView(frame: .zero)
        view.document = document
        view.setCurrentSelection(page.selection(for: NSRange(location: 0, length: 5)), animate: false)
        #expect(view.currentSelection?.string == "first")
        #expect(view.handleTextSelectionKey("l", eventType: .keyDown))
        let firstMove = try #require(page.selection(for: NSRange(location: 0, length: 6)))
        #expect(view.currentSelection?.range(at: 0, on: page) == firstMove.range(at: 0, on: page))
        for extra in otherPages { extra.resetCounts() }

        for _ in 0..<10 { #expect(view.handleTextSelectionKey("l", eventType: .keyDown)) }

        let expected = try #require(page.selection(for: NSRange(location: 0, length: 16)))
        #expect(view.currentSelection?.range(at: 0, on: page) == expected.range(at: 0, on: page))
        #expect(otherPages.allSatisfy { $0.characterCountReads == 0 && $0.stringReads == 0 })
    }

    @Test
    @MainActor
    func repeatedNavigationReadsOtherPagesOnlyOnce() throws {
        let document = PDFDocument()
        let pages = (0..<300).map { _ in CountingTextPage(text: "first second third\nfourth fifth") }
        for (index, page) in pages.enumerated() { document.insert(page, at: index) }
        let view = VellumPDFView(frame: .zero)
        view.document = document
        for page in pages { page.resetCounts() }

        let starts = view.textPageStarts(in: document)
        #expect(starts == (0...pages.count).map { $0 * ("first second third\nfourth fifth" as NSString).length })
        #expect(pages.allSatisfy { $0.characterCountReads == 1 })
        #expect(view.wordForwardOffset(from: 0, in: document, pageStarts: starts) == 6)
        let firstLines = view.textLines(onPageAt: 0, pageStarts: starts)
        let firstOffsets = firstLines.flatMap(\.characters).map(\.globalOffset).sorted()
        #expect(firstOffsets == Array(0..<18) + Array(19..<31))
        #expect(pages[0].stringReads > 0 && pages[0].characterBoundsReads > 0)
        #expect(pages.dropFirst().allSatisfy { $0.stringReads == 0 })
        for page in pages { page.resetCounts() }

        for _ in 0..<10 {
            #expect(view.textPageStarts(in: document) == starts)
            #expect(view.wordForwardOffset(from: 0, in: document, pageStarts: starts) == 6)
            #expect(view.wordBackwardOffset(from: 12, in: document, pageStarts: starts) == 6)
            #expect(view.wordEndOffset(from: 0, in: document, pageStarts: starts) == 5)
            #expect(view.textLines(onPageAt: 0, pageStarts: starts)
                .flatMap(\.characters).map(\.globalOffset).sorted() == firstOffsets)
        }

        #expect(pages.dropFirst().allSatisfy { $0.characterCountReads == 0 && $0.stringReads == 0 })
        #expect(pages.allSatisfy { $0.characterBoundsReads == 0 && $0.stringReads == 0 })
    }

    @Test
    @MainActor
    func wordNavigationCrossesPageBoundariesWithoutReadingLaterPages() {
        let document = PDFDocument()
        let pages = ["first", " second", " third"].map { CountingTextPage(text: $0) }
        for (index, page) in pages.enumerated() { document.insert(page, at: index) }
        let view = VellumPDFView(frame: .zero)
        view.document = document
        for page in pages { page.resetCounts() }
        let starts = view.textPageStarts(in: document)

        #expect(view.wordForwardOffset(from: 0, in: document, pageStarts: starts) == 6)
        #expect(pages[2].stringReads == 0)
        #expect(view.wordBackwardOffset(from: 12, in: document, pageStarts: starts) == 6)
        #expect(view.wordEndOffset(from: 6, in: document, pageStarts: starts) == 12)
    }

    @Test
    @MainActor
    func geometryChangesAndDocumentChangesInvalidateCachedData() throws {
        let document = PDFDocument()
        let page = CountingTextPage(text: "first second")
        document.insert(page, at: 0)
        let view = VellumPDFView(frame: .zero)
        view.document = document
        let starts = view.textPageStarts(in: document)
        let first = try #require(view.textLines(onPageAt: 0, pageStarts: starts).first)
        page.resetCounts()

        page.rotation = 90
        let rotated = try #require(view.textLines(onPageAt: 0, pageStarts: starts).first)
        #expect(page.characterBoundsReads > 0)
        #expect(rotated.characters.first?.centerX != first.characters.first?.centerX)
        page.resetCounts()
        page.setBounds(CGRect(x: 20, y: 30, width: 500, height: 700), for: .cropBox)
        _ = view.textLines(onPageAt: 0, pageStarts: starts)
        #expect(page.characterBoundsReads > 0)

        let replacement = PDFDocument()
        replacement.insert(CountingTextPage(text: "replacement"), at: 0)
        view.document = replacement
        #expect(view.textPageStarts(in: replacement) == [0, 11])
        #expect(view.documentText(in: replacement) == "replacement")
        replacement.insert(CountingTextPage(text: "next"), at: 1)
        #expect(view.textPageStarts(in: replacement) == [0, 11, 15])
        #expect(view.documentText(in: replacement) == "replacementnext")
    }
}

private final class CountingTextPage: PDFPage {
    private let text: String
    var characterCountReads = 0
    var stringReads = 0
    var characterBoundsReads = 0

    init(text: String) {
        self.text = text
        super.init()
        setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
    }

    override var numberOfCharacters: Int {
        characterCountReads += 1
        return (text as NSString).length
    }

    override var string: String? {
        stringReads += 1
        return text
    }

    override func characterBounds(at index: Int) -> CGRect {
        characterBoundsReads += 1
        return CGRect(x: 72 + (index % 18) * 10, y: 720 - (index / 18) * 25, width: 8, height: 16)
    }

    func resetCounts() {
        characterCountReads = 0
        stringReads = 0
        characterBoundsReads = 0
    }
}

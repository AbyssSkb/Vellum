import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Outline reading locations")
struct OutlineReadingMatcherTests {
    @Test
    func samePageSectionsUsePositionAndDuplicateDestinationsUseTheDeepestItem() {
        let document = makeDocument()
        let page = document.page(at: 0)!
        let first = item("0", page: page, y: 700)
        let nested = item("0.0", page: page, y: 700, parent: first)
        let later = item("0.1", page: page, y: 400, parent: first)
        first.children = [nested, later]
        #expect(OutlineReadingMatcher.item(for: PDFDestination(page: page, at: NSPoint(x: 300, y: 750)),
                                          in: [first]) == nil)
        #expect(OutlineReadingMatcher.item(for: PDFDestination(page: page, at: NSPoint(x: 300, y: 600)),
                                          in: [first]) === nested)
        #expect(OutlineReadingMatcher.item(for: PDFDestination(page: page, at: NSPoint(x: 300, y: 350)),
                                          in: [first]) === later)
        #expect(OutlineReadingMatcher.item(for: PDFDestination(page: document.page(at: 1)!, at: NSPoint(x: 300, y: 750)),
                                          in: [first]) === later)
    }

    @Test(arguments: [0, 90, 180, 270, -90])
    func croppedRotatedBookmarksFollowTheirDisplayedVerticalPositions(rotation: Int) {
        let document = makeDocument()
        let page = document.page(at: 0)!
        page.setBounds(NSRect(x: 40, y: 60, width: 400, height: 600), for: .cropBox)
        page.rotation = rotation
        let geometry = PDFPageDisplayGeometry(page: page, box: .cropBox)
        func anchor(_ id: String, position: CGFloat) -> PDFOutlineItem {
            PDFOutlineItem(id: id, title: id,
                           destination: PDFDestination(page: page, at: geometry.pagePoint(forDisplayPoint: NSPoint(
                            x: geometry.bounds.midX, y: geometry.bounds.maxY - position
                           ))), pageIndex: 0, parent: nil)
        }
        let first = anchor("0", position: 30)
        let second = anchor("1", position: 160)
        let reading = PDFDestination(page: page, at: geometry.pagePoint(forDisplayPoint: NSPoint(
            x: geometry.bounds.midX, y: geometry.bounds.maxY - 120
        )))
        #expect(OutlineReadingMatcher.item(for: reading, in: [first, second]) === first)
    }

    @Test
    func explicitBookmarkRemainsStableAcrossSamePageLayoutMovement() {
        let document = makeDocument()
        let page = document.page(at: 0)!
        let first = item("0", page: page, y: 700)
        let second = item("1", page: page, y: 400)
        let movedAnchor = PDFDestination(page: page, at: NSPoint(x: 300, y: 350))
        #expect(OutlineReadingMatcher.item(for: movedAnchor, in: [first, second], preferredID: first.id) === first)
        #expect(OutlineReadingMatcher.item(for: movedAnchor, in: [first, second]) === second)
        let nextPage = PDFDestination(page: document.page(at: 1)!, at: NSPoint(x: 300, y: 750))
        #expect(OutlineReadingMatcher.item(for: nextPage, in: [first, second], preferredID: first.id) === second)
    }

    @Test
    func foreignInvalidAndUnspecifiedDestinationsAreHandledWithoutInventingASection() {
        let document = makeDocument()
        let otherDocument = makeDocument()
        let page = document.page(at: 0)!
        let foreign = item("foreign", page: otherDocument.page(at: 0)!, y: 700)
        let invalid = item("invalid", page: page, y: .nan)
        let reading = PDFDestination(page: page, at: NSPoint(x: 300, y: 600))
        #expect(OutlineReadingMatcher.item(for: reading, in: [foreign, invalid]) == nil)
        let pageOnly = item("page", page: page, y: kPDFDestinationUnspecifiedValue)
        #expect(OutlineReadingMatcher.item(for: reading, in: [pageOnly]) === pageOnly)
    }

    private func makeDocument() -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<2 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        return document
    }

    private func item(_ id: String, page: PDFPage, y: CGFloat, parent: PDFOutlineItem? = nil) -> PDFOutlineItem {
        PDFOutlineItem(id: id, title: id, destination: PDFDestination(page: page, at: NSPoint(x: 300, y: y)),
                       pageIndex: page.document?.index(for: page), parent: parent)
    }
}

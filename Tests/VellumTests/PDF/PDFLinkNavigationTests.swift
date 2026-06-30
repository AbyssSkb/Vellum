import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF link navigation")
struct PDFLinkNavigationTests {
    @Test
    func destinationLinkRecordsJumpSource() {
        let page = PDFPage()
        let annotation = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        annotation.destination = PDFDestination(page: page, at: .zero)

        #expect(PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }

    @Test
    func goToActionLinkRecordsJumpSource() {
        let page = PDFPage()
        let annotation = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        annotation.action = PDFActionGoTo(destination: PDFDestination(page: page, at: .zero))

        #expect(PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }

    @Test
    func urlLinkDoesNotRecordJumpSource() {
        let annotation = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        annotation.action = PDFActionURL(url: URL(string: "https://example.com")!)

        #expect(!PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }

    @Test
    func nonLinkAnnotationDoesNotRecordJumpSource() {
        let annotation = PDFAnnotation(bounds: .zero, forType: .highlight, withProperties: nil)

        #expect(!PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }
}

import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF link navigation")
struct PDFLinkNavigationTests {
    @Test
    func linkActionsResolveDestinationsURLsAndNamedActions() throws {
        let destination = PDFDestination(page: PDFPage(), at: NSPoint(x: 20, y: 30))
        let internalLink = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        internalLink.destination = destination
        let resolved = try #require(PDFLinkNavigation.action(for: internalLink) as? PDFActionGoTo).destination
        #expect(resolved.page === destination.page)
        #expect(resolved.point == destination.point)

        let url = try #require(URL(string: "https://example.com/reference"))
        let externalLink = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        externalLink.url = url
        #expect((PDFLinkNavigation.action(for: externalLink) as? PDFActionURL)?.url == url)

        let namedLink = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        namedLink.action = PDFActionNamed(name: .nextPage)
        #expect((PDFLinkNavigation.action(for: namedLink) as? PDFActionNamed)?.name == .nextPage)
        #expect(PDFLinkNavigation.action(for: PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)) == nil)
    }

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

    @Test(arguments: [PDFActionNamedName.nextPage, .previousPage, .firstPage, .lastPage, .goBack, .goForward, .goToPage])
    func namedNavigationLinkRecordsJumpSource(name: PDFActionNamedName) {
        let annotation = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        annotation.action = PDFActionNamed(name: name)

        #expect(PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }

    @Test(arguments: [PDFActionNamedName.none, .find, .print, .zoomIn, .zoomOut])
    func namedNonNavigationLinkDoesNotRecordJumpSource(name: PDFActionNamedName) {
        let annotation = PDFAnnotation(bounds: .zero, forType: .link, withProperties: nil)
        annotation.action = PDFActionNamed(name: name)

        #expect(!PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }

    @Test
    func nonLinkAnnotationDoesNotRecordJumpSource() {
        let annotation = PDFAnnotation(bounds: .zero, forType: .highlight, withProperties: nil)

        #expect(!PDFLinkNavigation.shouldRecordJumpSource(for: annotation))
    }
}

import Foundation
import Testing
@testable import VellumCore

@MainActor
@Suite("Reader models")
struct ReaderModelTests {
    @Test
    func pdfTabTitleUsesFileNameWithoutExtension() {
        let tab = PDFTab(url: URL(fileURLWithPath: "/tmp/Research Paper.pdf"), document: nil)

        #expect(tab.title == "Research Paper")
    }

    @Test
    func untitledPDFTabHasFallbackTitle() {
        let tab = PDFTab(url: nil, document: nil)

        #expect(tab.title == "Untitled")
    }

    @Test
    func highlightColorsCycleThroughCatalog() {
        var color = HighlightColor.yellow
        var visited: [HighlightColor] = []

        for _ in HighlightColor.allCases {
            visited.append(color)
            color = color.next
        }

        #expect(visited == HighlightColor.allCases)
        #expect(color == .yellow)
    }
}

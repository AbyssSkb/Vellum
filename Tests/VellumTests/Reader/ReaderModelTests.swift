import Foundation
import Testing
@testable import VellumCore

@MainActor
@Suite("Reader models")
struct ReaderModelTests {
    @Test
    func documentTabTitleUsesFileNameWithoutExtension() {
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/Research Paper.pdf"), document: nil)

        #expect(tab.title == "Research Paper")
    }

    @Test
    func markdownDocumentTabUsesMarkdownFileTitle() {
        let document = MarkdownDocument(url: URL(fileURLWithPath: "/tmp/Notes.md"), source: "# Notes")
        let tab = DocumentTab(url: document.url, markdownDocument: document)

        #expect(tab.title == "Notes")
        #expect(tab.markdownDocument == document)
    }

    @Test
    func untitledDocumentTabHasFallbackTitle() {
        let tab = DocumentTab(url: nil, document: nil)

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

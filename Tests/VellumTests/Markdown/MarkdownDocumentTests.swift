import Foundation
import Testing
@testable import VellumCore

@Suite("Markdown document")
struct MarkdownDocumentTests {
    @Test
    func lineRangesIncludeTrailingEmptyLine() {
        let ranges = MarkdownSourceLineIndexer.ranges(in: "one\ntwo\n")

        #expect(ranges.count == 3)
        #expect(ranges.last?.length == 0)
    }

    @Test
    func outlineRecognizesTyporaStyleHeadingsWithoutCodeBlockNoise() {
        let source = """
        Title
        =====

        ## Section ##

        ```swift
        # Not a heading
        ```

            # Also code

        Subsection
        ----------
        """
        let document = MarkdownDocument(url: URL(fileURLWithPath: "/tmp/notes.md"), source: source)
        let flattened = document.outlineItems.flattened()

        #expect(flattened.map(\.title) == ["Title", "Section", "Subsection"])
        #expect(flattened.map(\.level) == [1, 2, 2])
        #expect(flattened.map(\.sourceLineIndex) == [0, 3, 11])
    }
}

import Foundation
import Testing
@testable import VellumCore

@Suite("Document coordinator")
struct DocumentCoordinatorTests {
    @Test
    func openingTabsKeepsLoadableURLsInOrder() {
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let missing = URL(fileURLWithPath: "/tmp/missing.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let coordinator = DocumentCoordinator(
            loader: StubDocumentTabLoader(loadableURLs: [first, second])
        )

        let tabs = coordinator.openTabs(for: [first, missing, second])

        #expect(tabs.map(\.url) == [first, second])
        #expect(tabs.allSatisfy { $0.snapshot == .initial })
    }

    @Test
    func markdownURLsUseMarkdownLoader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumMarkdownTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.md")
        try "# Notes\n\n- [x] task\n".write(to: url, atomically: true, encoding: .utf8)

        let tab = try #require(DocumentCoordinator().openTab(for: url))

        #expect(tab.url == url)
        #expect(tab.markdownDocument?.source.contains("# Notes") == true)
        #expect(tab.markdownDocument?.outlineItems.first?.title == "Notes")
        #expect(tab.snapshot == .initial)
    }

    @Test
    func markdownExtensionsAreRecognizedCaseInsensitively() {
        #expect(DocumentCoordinator.isMarkdownURL(URL(fileURLWithPath: "/tmp/a.md")))
        #expect(DocumentCoordinator.isMarkdownURL(URL(fileURLWithPath: "/tmp/a.MARKDOWN")))
        #expect(DocumentCoordinator.isMarkdownURL(URL(fileURLWithPath: "/tmp/a.mdown")))
        #expect(!DocumentCoordinator.isMarkdownURL(URL(fileURLWithPath: "/tmp/a.pdf")))
    }

    private struct StubDocumentTabLoader: DocumentTabLoading {
        let loadableURLs: Set<URL>

        func tab(for url: URL) -> DocumentTab? {
            guard loadableURLs.contains(url) else { return nil }
            return DocumentTab(url: url, document: nil, snapshot: .initial)
        }
    }
}

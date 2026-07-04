import Foundation
import UniformTypeIdentifiers

struct DocumentCoordinator {
    private let loader: any DocumentTabLoading
    private let markdownLoader: MarkdownDocumentLoader

    init(loader: any DocumentTabLoading = PDFDocumentLoader(), markdownLoader: MarkdownDocumentLoader = MarkdownDocumentLoader()) {
        self.loader = loader
        self.markdownLoader = markdownLoader
    }

    func openTab(for url: URL) -> DocumentTab? {
        if Self.isMarkdownURL(url) {
            return markdownLoader.tab(for: url)
        }
        return loader.tab(for: url)
    }

    func openTabs(for urls: [URL]) -> [DocumentTab] {
        urls.compactMap(openTab(for:))
    }

    static func isMarkdownURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown"].contains(pathExtension)
    }
}

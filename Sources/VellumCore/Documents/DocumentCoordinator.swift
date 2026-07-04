import Foundation

struct DocumentCoordinator {
    private let loader: any PDFTabLoading

    init(loader: any PDFTabLoading = PDFDocumentLoader()) {
        self.loader = loader
    }

    func openTab(for url: URL) -> PDFTab? {
        loader.tab(for: url)
    }

    func openTabs(for urls: [URL]) -> [PDFTab] {
        urls.compactMap(openTab(for:))
    }
}

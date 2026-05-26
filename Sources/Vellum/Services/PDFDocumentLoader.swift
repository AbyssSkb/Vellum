import PDFKit

protocol PDFTabLoading {
    func tab(for url: URL) -> PDFTab?
}

struct PDFDocumentLoader: PDFTabLoading {
    func tab(for url: URL) -> PDFTab? {
        guard let document = PDFDocument(url: url) else { return nil }
        return PDFTab(url: url, document: document, snapshot: .initial)
    }
}

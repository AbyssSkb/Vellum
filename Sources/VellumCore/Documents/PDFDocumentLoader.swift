import PDFKit

protocol DocumentTabLoading {
    func tab(for url: URL) -> DocumentTab?
}

struct PDFDocumentLoader: DocumentTabLoading {
    func tab(for url: URL) -> DocumentTab? {
        guard let document = PDFDocument(url: url) else { return nil }
        return DocumentTab(url: url, document: document, snapshot: .initial)
    }
}

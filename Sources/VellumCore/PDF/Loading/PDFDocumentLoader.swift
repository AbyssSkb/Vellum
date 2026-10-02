import PDFKit

protocol PDFTabLoading {
    func tab(for url: URL) -> PDFTab?
}

struct PDFDocumentLoader: PDFTabLoading {
    func tab(for url: URL) -> PDFTab? {
        let persistence = PDFAnnotationPersistence(url: url)
        guard let document = PDFDocument(url: url) else { return nil }
        PDFAnnotationPersistence.register(document, state: persistence)
        return PDFTab(url: url, document: document, snapshot: .initial)
    }
}

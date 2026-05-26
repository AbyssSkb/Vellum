import PDFKit

enum PDFDocumentLoader {
    static func tab(for url: URL) -> PDFTab? {
        guard let document = PDFDocument(url: url) else { return nil }
        return PDFTab(url: url, document: document, snapshot: .initial)
    }
}

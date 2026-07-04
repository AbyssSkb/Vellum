import Foundation

struct MarkdownDocumentLoader {
    func tab(for url: URL) -> DocumentTab? {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let document = MarkdownDocument(url: url.standardizedFileURL, source: source)
        return DocumentTab(url: url, markdownDocument: document, snapshot: .initial)
    }
}

import Foundation
import PDFKit

enum ReaderDocument: Equatable {
    case pdf(PDFDocument)
    case markdown(MarkdownDocument)

    static func == (lhs: ReaderDocument, rhs: ReaderDocument) -> Bool {
        switch (lhs, rhs) {
        case (.pdf(let lhsDocument), .pdf(let rhsDocument)):
            return lhsDocument === rhsDocument
        case (.markdown(let lhsDocument), .markdown(let rhsDocument)):
            return lhsDocument == rhsDocument
        default:
            return false
        }
    }
}

struct DocumentTab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var content: ReaderDocument?
    var snapshot: ReaderSnapshot?

    var document: PDFDocument? {
        guard case .pdf(let document) = content else { return nil }
        return document
    }

    var markdownDocument: MarkdownDocument? {
        guard case .markdown(let document) = content else { return nil }
        return document
    }

    var title: String {
        url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    init(id: UUID = UUID(), url: URL?, document: PDFDocument?, snapshot: ReaderSnapshot? = nil) {
        self.id = id
        self.url = url
        self.content = document.map(ReaderDocument.pdf)
        self.snapshot = snapshot
    }

    init(id: UUID = UUID(), url: URL?, markdownDocument: MarkdownDocument, snapshot: ReaderSnapshot? = nil) {
        self.id = id
        self.url = url
        self.content = .markdown(markdownDocument)
        self.snapshot = snapshot
    }
}

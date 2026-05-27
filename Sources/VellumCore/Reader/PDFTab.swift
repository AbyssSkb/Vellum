import Foundation
import PDFKit

struct PDFTab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var document: PDFDocument?
    var snapshot: ReaderSnapshot?

    var title: String {
        url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    init(id: UUID = UUID(), url: URL?, document: PDFDocument?, snapshot: ReaderSnapshot? = nil) {
        self.id = id
        self.url = url
        self.document = document
        self.snapshot = snapshot
    }
}

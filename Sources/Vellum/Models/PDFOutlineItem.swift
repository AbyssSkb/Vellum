import Foundation
import PDFKit

final class PDFOutlineItem: NSObject {
    let id: String
    let title: String
    let destination: PDFDestination?
    let pageIndex: Int?
    weak var parent: PDFOutlineItem?
    var children: [PDFOutlineItem] = []

    init(
        id: String,
        title: String,
        destination: PDFDestination?,
        pageIndex: Int?,
        parent: PDFOutlineItem?
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.pageIndex = pageIndex
        self.parent = parent
        super.init()
    }
}

enum PDFOutlineBuilder {
    static func items(for document: PDFDocument) -> [PDFOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        return children(of: root, document: document, parent: nil, path: "")
    }

    private static func children(
        of outline: PDFOutline,
        document: PDFDocument,
        parent: PDFOutlineItem?,
        path: String
    ) -> [PDFOutlineItem] {
        (0..<outline.numberOfChildren).compactMap { index in
            guard let child = outline.child(at: index) else { return nil }

            let itemPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
            let destination = child.destination
            let pageIndex = destination?.page.map { document.index(for: $0) }
            let fallbackTitle = pageIndex.map { "Page \($0 + 1)" } ?? "Untitled"
            let title = child.label?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? fallbackTitle

            let item = PDFOutlineItem(
                id: itemPath,
                title: title,
                destination: destination,
                pageIndex: pageIndex,
                parent: parent
            )
            item.children = children(of: child, document: document, parent: item, path: itemPath)
            return item
        }
    }
}
extension Array where Element == PDFOutlineItem {
    func flattened() -> [PDFOutlineItem] {
        flatMap { item in
            [item] + item.children.flattened()
        }
    }
}

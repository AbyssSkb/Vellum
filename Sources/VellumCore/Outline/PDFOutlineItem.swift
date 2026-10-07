import Foundation
import PDFKit

final class PDFOutlineItem: NSObject {
    let id: String
    let title: String
    let destination: PDFDestination?
    let action: PDFAction?
    let pageIndex: Int?
    weak var parent: PDFOutlineItem?
    var children: [PDFOutlineItem] = []

    init(
        id: String,
        title: String,
        destination: PDFDestination?,
        pageIndex: Int?,
        parent: PDFOutlineItem?,
        action: PDFAction? = nil
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.action = action
        self.pageIndex = pageIndex
        self.parent = parent
        super.init()
    }

    @MainActor
    @discardableResult
    func activate(in appState: AppState) -> Bool {
        if let action {
            appState.jumpToOutlineAction(action, itemID: id)
        } else if let destination {
            appState.jumpToOutlineDestination(destination, itemID: id)
        } else {
            return false
        }
        return true
    }
}

enum PDFOutlineBuilder {
    static func items(for document: PDFDocument, language: AppUILanguage = .saved()) -> [PDFOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        return children(of: root, document: document, language: language, parent: nil, path: "")
    }

    private static func children(
        of outline: PDFOutline,
        document: PDFDocument,
        language: AppUILanguage,
        parent: PDFOutlineItem?,
        path: String
    ) -> [PDFOutlineItem] {
        (0..<outline.numberOfChildren).compactMap { index in
            guard let child = outline.child(at: index) else { return nil }

            let itemPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
            let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
            let pageIndex = destination?.page.map { document.index(for: $0) }
            let fallbackTitle = pageIndex.map { language.text(.outlinePage($0 + 1)) } ?? language.text(.untitled)
            let title = child.label?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? fallbackTitle

            let item = PDFOutlineItem(
                id: itemPath,
                title: title,
                destination: destination,
                pageIndex: pageIndex,
                parent: parent,
                action: child.action
            )
            item.children = children(of: child, document: document, language: language, parent: item, path: itemPath)
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

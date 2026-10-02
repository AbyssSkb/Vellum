import Foundation

struct ClosedPDFTabHistory {
    private var tabs: [(url: URL, snapshot: ReaderSnapshot?)] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    mutating func remember(_ tab: PDFTab) {
        guard tab.document != nil, let url = tab.url else { return }
        tabs.append((url, tab.snapshot))

        if tabs.count > limit {
            tabs.removeFirst(tabs.count - limit)
        }
    }

    mutating func restore() -> (url: URL, snapshot: ReaderSnapshot?)? {
        tabs.popLast()
    }
}

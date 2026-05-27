struct ClosedPDFTabHistory {
    private var tabs: [PDFTab] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    mutating func remember(_ tab: PDFTab) {
        guard tab.document != nil else { return }
        tabs.append(tab)

        if tabs.count > limit {
            tabs.removeFirst(tabs.count - limit)
        }
    }

    mutating func restore() -> PDFTab? {
        tabs.popLast()
    }
}

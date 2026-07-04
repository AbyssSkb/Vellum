struct ClosedDocumentTabHistory {
    private var tabs: [DocumentTab] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    mutating func remember(_ tab: DocumentTab) {
        guard tab.content != nil else { return }
        tabs.append(tab)

        if tabs.count > limit {
            tabs.removeFirst(tabs.count - limit)
        }
    }

    mutating func restore() -> DocumentTab? {
        tabs.popLast()
    }
}

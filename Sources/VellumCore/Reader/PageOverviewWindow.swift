enum PageOverviewWindow {
    static func slots(selectedIndex: Int, pageCount: Int, visibleCount: Int) -> [Int?] {
        guard pageCount > 0, visibleCount > 0 else { return [] }

        let centerSlot = visibleCount / 2
        return (0..<visibleCount).map { slot in
            let pageIndex = selectedIndex + slot - centerSlot
            guard pageIndex >= 0, pageIndex < pageCount else { return nil }
            return pageIndex
        }
    }
}

import PDFKit

enum OutlineReadingMatcher {
    static func item(
        for destination: PDFDestination,
        in items: [PDFOutlineItem],
        preferredID: String? = nil
    ) -> PDFOutlineItem? {
        guard let page = destination.page, let document = page.document,
              let readingPosition = position(of: destination) else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let allItems = items.flattened()
        if let preferredID,
           let preferred = allItems.first(where: { $0.id == preferredID }),
           preferred.destination?.page === page {
            return preferred
        }

        var match: PDFOutlineItem?
        var matchedPage = -1
        var matchedPosition: CGFloat = -1
        var matchedDepth = -1
        for item in allItems {
            guard let anchor = item.destination, let anchorPage = anchor.page,
                  anchorPage.document === document, let anchorPosition = position(of: anchor) else { continue }
            let anchorIndex = document.index(for: anchorPage)
            guard anchorIndex != NSNotFound, anchorIndex <= pageIndex,
                  anchorIndex < pageIndex || anchorPosition <= readingPosition else { continue }
            var depth = 0
            var parent = item.parent
            while let ancestor = parent { depth += 1; parent = ancestor.parent }
            if anchorIndex > matchedPage
                || (anchorIndex == matchedPage && anchorPosition > matchedPosition)
                || (anchorIndex == matchedPage && anchorPosition == matchedPosition && depth > matchedDepth) {
                match = item
                matchedPage = anchorIndex
                matchedPosition = anchorPosition
                matchedDepth = depth
            }
        }
        return match
    }

    private static func position(of destination: PDFDestination) -> CGFloat? {
        guard let page = destination.page else { return nil }
        if destination.point.y == kPDFDestinationUnspecifiedValue { return 0 }
        let geometry = PDFPageDisplayGeometry(page: page, box: .cropBox)
        let point = geometry.point(forPagePoint: destination.point)
        guard point.y.isFinite else { return nil }
        return min(max(0, geometry.bounds.maxY - point.y), geometry.bounds.height)
    }
}

@preconcurrency import AppKit
@preconcurrency import PDFKit
import Combine

@MainActor
final class TabSwitcherPreviewStore: ObservableObject {
    private struct Preview {
        let document: PDFDocument
        let loader: PageOverviewThumbnailLoader
        var pageIndex: Int
        var maximumPixelSize: NSSize
    }

    @Published private(set) var images: [PDFTab.ID: NSImage] = [:]
    private var previews: [PDFTab.ID: Preview] = [:]

    func update(tabs: [PDFTab], maximumPixelSize: NSSize) {
        let ids = Set(tabs.map(\.id))
        for id in previews.keys where !ids.contains(id) {
            previews.removeValue(forKey: id)?.loader.cancel()
            images.removeValue(forKey: id)
        }

        for tab in tabs {
            guard let document = tab.document, document.pageCount > 0,
                  maximumPixelSize.width > 0, maximumPixelSize.height > 0 else {
                previews.removeValue(forKey: tab.id)?.loader.cancel()
                images.removeValue(forKey: tab.id)
                continue
            }
            let pageIndex = min(max(tab.snapshot?.pageIndex ?? 0, 0), document.pageCount - 1)
            let previous = previews[tab.id]
            if let previous, previous.document === document,
               previous.pageIndex == pageIndex,
               previous.maximumPixelSize.width >= maximumPixelSize.width,
               previous.maximumPixelSize.height >= maximumPixelSize.height {
                continue
            }
            let loader: PageOverviewThumbnailLoader
            if let previous, previous.document === document {
                loader = previous.loader
                if previous.pageIndex != pageIndex { images.removeValue(forKey: tab.id) }
            } else {
                previous?.loader.cancel()
                images.removeValue(forKey: tab.id)
                loader = PageOverviewThumbnailLoader()
            }
            previews[tab.id] = Preview(document: document, loader: loader,
                                       pageIndex: pageIndex, maximumPixelSize: maximumPixelSize)
            loader.update(document: document, pageIndexes: [pageIndex], selectedIndex: pageIndex,
                          maximumPixelSize: maximumPixelSize) { [weak self, weak loader] in
                guard let self, let loader, let current = self.previews[tab.id],
                      current.loader === loader, current.pageIndex == pageIndex else { return }
                self.images[tab.id] = loader.images[pageIndex]
            }
            if let cached = loader.images[pageIndex] { images[tab.id] = cached }
        }
    }

    func cancel() {
        previews.values.forEach { $0.loader.cancel() }
        previews.removeAll()
        images.removeAll()
    }
}

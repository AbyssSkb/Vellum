@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF outline coordinator")
struct PDFOutlineCoordinatorTests {
    @Test
    func switchingDocumentsWithIdenticalOutlinesReplacesDestinations() {
        let firstDocument = PDFDocument()
        let secondDocument = PDFDocument()
        firstDocument.insert(PDFPage(), at: 0)
        secondDocument.insert(PDFPage(), at: 0)
        let firstItem = item(for: firstDocument)
        let secondItem = item(for: secondDocument)
        let coordinator = PDFOutlineView.Coordinator(items: [firstItem], appState: AppState())
        let outlineView = NSOutlineView()

        #expect(coordinator.updateItemsIfNeeded([secondItem], in: outlineView))
        let displayedItem = coordinator.outlineView(outlineView, child: 0, ofItem: nil) as? PDFOutlineItem
        #expect(displayedItem?.destination?.page?.document === secondDocument)
        #expect(!coordinator.updateItemsIfNeeded([item(for: secondDocument)], in: outlineView))
    }

    private func item(for document: PDFDocument) -> PDFOutlineItem {
        PDFOutlineItem(
            id: "0",
            title: "Chapter 1",
            destination: PDFDestination(page: document.page(at: 0)!, at: .zero),
            pageIndex: 0,
            parent: nil
        )
    }
}

import Foundation
import Testing
@testable import VellumCore

@Suite("Document coordinator")
struct DocumentCoordinatorTests {
    @Test
    func openingTabsKeepsLoadableURLsInOrder() {
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let missing = URL(fileURLWithPath: "/tmp/missing.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let coordinator = DocumentCoordinator(
            loader: StubPDFTabLoader(loadableURLs: [first, second])
        )

        let tabs = coordinator.openTabs(for: [first, missing, second])

        #expect(tabs.map(\.url) == [first, second])
        #expect(tabs.allSatisfy { $0.snapshot == .initial })
    }

    private struct StubPDFTabLoader: PDFTabLoading {
        let loadableURLs: Set<URL>

        func tab(for url: URL) -> PDFTab? {
            guard loadableURLs.contains(url) else { return nil }
            return PDFTab(url: url, document: nil, snapshot: .initial)
        }
    }
}

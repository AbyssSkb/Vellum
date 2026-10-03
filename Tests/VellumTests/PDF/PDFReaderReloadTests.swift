import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("PDF reader reload")
struct PDFReaderReloadTests {
    @Test @MainActor
    func replacingDocumentKeepsReaderAndDiscardsOldDocumentState() async throws {
        _ = NSApplication.shared
        let suiteName = "Vellum.ReaderReload.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false,
            notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
        ))
        let original = try makeDocument(text: "alpha")
        let replacement = try makeDocument(text: "beta")
        let tab = PDFTab(url: URL(fileURLWithPath: "/tmp/reader-reload.pdf"), document: original)
        _ = appState.tabStore.openInNewTabs([tab])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hostingView = NSHostingView(rootView: PDFReader(
            tabID: tab.id, document: original, snapshot: nil, isActive: true
        ).environmentObject(appState))
        hostingView.frame = window.contentView!.bounds
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { appState.activeReaderController != nil }
        let reader = try #require(appState.activeReaderController as? VellumPDFView)
        defer { reader.searchController?.clear() }

        reader.beginSearchCommand()
        let oldSearchController = try #require(reader.searchController)
        let searchOverlay = try #require(reader.subviews.first { searchField(in: $0) != nil })
        enter("alpha", into: try #require(searchField(in: reader)))
        reader.vimSearchNext()
        try #require(oldSearchController.hasVisibleHighlights)
        try #require(reader.beginPageOverview())
        let overviewOverlay = try #require(reader.pageOverviewController?.overlay)
        let oldPage = try #require(original.page(at: 0))
        let selection = try #require(oldPage.selection(for: NSRange(location: 0, length: 5)))
        reader.setCurrentSelection(selection, animate: false)
        reader.textSelectionNavigationState = VimTextSelectionNavigationState(
            anchorOffset: 0, extentOffset: 5, preferredX: nil, anchorCaret: nil, extentCaret: nil
        )
        let annotation = PDFAnnotation(bounds: selection.bounds(for: oldPage), forType: .highlight, withProperties: nil)
        reader.aiInteraction.suppressedHoverKey = "old"
        reader.aiInteraction.suppressedHoverAnnotation = annotation
        reader.aiInteraction.suppressedHoverText = "old"
        let snapshot = ReaderSnapshot(
            pageIndex: 0, pointOnPage: NSPoint(x: 80, y: 600), scrollOrigin: nil,
            scaleFactor: 1.25, autoScales: false
        )
        reader.jumpBackStack = [snapshot]
        reader.jumpForwardStack = [snapshot]

        hostingView.rootView = PDFReader(
            tabID: tab.id, document: replacement, snapshot: snapshot, isActive: true
        ).environmentObject(appState)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { reader.document === replacement && reader.pendingRestoreAction == nil }

        #expect(appState.activeReaderController === reader)
        #expect(reader.scaleFactor == snapshot.scaleFactor)
        #expect(reader.currentPage === replacement.page(at: snapshot.pageIndex))
        #expect(reader.pageOverviewController == nil)
        #expect(overviewOverlay.superview == nil)
        #expect(reader.searchController == nil)
        #expect(searchOverlay.superview == nil)
        #expect(!oldSearchController.canHandleEscape)
        #expect(reader.highlightedSelections?.isEmpty != false)
        #expect(reader.currentSelection == nil)
        #expect(reader.textSelectionNavigationState == nil)
        #expect(reader.jumpBackStack.isEmpty)
        #expect(reader.jumpForwardStack.isEmpty)
        #expect(reader.aiInteraction.suppressedHoverKey == nil)
        #expect(reader.aiInteraction.suppressedHoverAnnotation == nil)
        #expect(reader.aiInteraction.suppressedHoverText == nil)

        reader.beginSearchCommand()
        let newSearchController = try #require(reader.searchController)
        #expect(newSearchController !== oldSearchController)
        enter("beta", into: try #require(searchField(in: reader)))
        reader.vimSearchNext()
        #expect(newSearchController.activeSearchSelection?.string == "beta")
        #expect(newSearchController.activeSearchSelection?.pages.first === replacement.page(at: 0))
    }

    @MainActor
    private func makeDocument(text: String) throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(at: NSPoint(x: 72, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    @MainActor
    private func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { searchField(in: $0) }.first
    }

    @MainActor
    private func enter(_ query: String, into field: NSTextField) {
        field.stringValue = query
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

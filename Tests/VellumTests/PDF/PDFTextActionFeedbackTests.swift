@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF text action feedback")
struct PDFTextActionFeedbackTests {
    @Test
    func missingTextExplainsHighlightAndCopyWithoutChangingTheClipboard() throws {
        let (window, view) = try makeReader()
        defer { close(window, view) }
        let clipboardChangeCount = NSPasteboard.general.changeCount

        view.vimHighlightSelection(color: .yellow)
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noTextToHighlight))
        #expect(view.document?.page(at: 0)?.annotations.isEmpty == true)

        view.vimCopySelection()
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noTextToCopy))
        #expect(NSPasteboard.general.changeCount == clipboardChangeCount)
        #expect(!view.vimDeleteHighlightsForSelection())
    }

    @Test
    func deletingAnUnhighlightedSelectionExplainsTheReasonAndPreservesIt() throws {
        let (window, view) = try makeReader()
        defer { close(window, view) }
        let selection = try wordSelection("alpha", in: view)
        view.setCurrentSelection(selection, animate: false)

        #expect(view.vimDeleteHighlightsForSelection())

        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noHighlightsInSelection))
        #expect(view.currentSelection?.string == "alpha")
    }

    @Test(arguments: [false, true])
    func copyingRealTextConfirmsTheResultAndPreservesSearchMatches(useSearch: Bool) async throws {
        let (window, view) = try makeReader()
        defer { close(window, view) }
        let clipboard = NSPasteboard.general
        let savedItems = (clipboard.pasteboardItems ?? []).map { item in
            let saved = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
        defer {
            clipboard.clearContents()
            if !savedItems.isEmpty { clipboard.writeObjects(savedItems) }
        }
        if useSearch {
            view.beginSearchCommand()
            let controller = try #require(view.searchController)
            let field = try #require(searchField(in: view))
            field.stringValue = "beta"
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            try await waitForTestCondition("Search provides a copy target") {
                !controller.isSearchPending && controller.activeSearchSelection?.string == "beta"
            }
            try #require(view.currentSelection == nil)
        } else {
            view.setCurrentSelection(try wordSelection("alpha", in: view), animate: false)
        }

        view.vimCopySelection()

        #expect(clipboard.string(forType: .string) == (useSearch ? "beta" : "alpha"))
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.textCopied))
        #expect(view.currentSelection == nil)
        if useSearch {
            #expect(view.searchController?.hasVisibleHighlights == true)
            #expect(view.searchController?.activeSearchSelection?.string == "beta")
        }
    }

    @Test
    func successfulHighlightUsesItsVisibleAnnotationAsFeedback() throws {
        let (window, view) = try makeReader()
        defer { close(window, view) }
        view.setCurrentSelection(try wordSelection("alpha", in: view), animate: false)

        view.vimHighlightSelection(color: .yellow)

        #expect(view.document?.page(at: 0)?.annotations.count == 1)
        #expect(view.currentSelection == nil)
        #expect(currentToast(in: window) == nil)
    }

    private func wordSelection(_ word: String, in view: VellumPDFView) throws -> PDFSelection {
        let page = try #require(view.document?.page(at: 0))
        let text = try #require(page.string) as NSString
        return try #require(page.selection(for: text.range(of: word)))
    }

    private func currentToast(in window: NSWindow) -> ToastView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
    }

    private func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { searchField(in: $0) }.first
    }

    private func makeReader() throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        view.document = try makeTextPDF(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        return (window, view)
    }

    private func close(_ window: NSWindow, _ view: VellumPDFView) {
        view.searchController?.clear()
        view.cancelPendingRestore()
        view.stopScrollAnimation()
        view.stopZoomState()
        view.readingPositionReportWorkItem?.cancel()
        view.readerStateSaveWorkItem?.cancel()
        window.contentView = nil
        window.close()
    }
}

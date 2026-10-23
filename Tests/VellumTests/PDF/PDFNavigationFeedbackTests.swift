import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF navigation feedback")
@MainActor
struct PDFNavigationFeedbackTests {
    @Test(arguments: [0, 1, 2, 3], [nil, "", " \n"] as [String?])
    func searchMovementExplainsMissingQuery(command: Int, query: String?) throws {
        let (window, view) = makeReader()
        defer { close(window, view) }
        if let query {
            view.beginSearchCommand()
            let field = try #require(textFields(in: view).first { $0.isEditable })
            enter(query, into: field)
        }
        let responder = window.firstResponder

        switch command {
        case 0: view.vimSearchNext()
        case 1: view.vimSearchPrevious()
        case 2: view.vimSearchBy(100)
        default: view.vimSearchBy(-100)
        }

        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noSearchQuery))
        #expect(view.jumpBackStack.isEmpty)
        #expect(window.firstResponder === responder)
    }

    @Test(arguments: [false, true])
    func searchSelectionExplainsMissingMatch(withController: Bool) {
        let (window, view) = makeReader()
        defer { close(window, view) }
        if withController { view.searchController = PDFSearchController(pdfView: view) }

        view.vimMaterializeSearchSelection()

        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.noSearchMatch))
        #expect(view.currentSelection == nil)
    }

    @Test
    func searchHUDKeepsItsPendingAndNoMatchFeedback() async throws {
        let (window, view) = makeReader()
        defer { close(window, view) }
        view.beginSearchCommand()
        let controller = try #require(view.searchController)
        let field = try #require(textFields(in: view).first { $0.isEditable })
        enter("missing", into: field)
        #expect(controller.isSearchPending)

        view.vimSearchBy(100)
        view.vimMaterializeSearchSelection()
        #expect(currentToast(in: window) == nil)
        try await waitForTestCondition("Search completes without matching text") { !controller.isSearchPending }

        view.vimSearchPrevious()
        view.vimMaterializeSearchSelection()
        #expect(currentToast(in: window) == nil)
        #expect(field.window === window)
        #expect(field.stringValue == "missing")
        #expect(controller.activeSearchSelection == nil)
    }

    @Test(arguments: [false, true])
    func emptyJumpHistoryExplainsItsBoundary(forward: Bool) {
        let (window, view) = makeReader()
        defer { close(window, view) }
        let originalPage = view.currentPage

        if forward { view.vimJumpForward() } else { view.vimJumpBack() }

        let text: AppText = forward ? .noLaterReadingPosition : .noEarlierReadingPosition
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(text))
        #expect(view.currentPage === originalPage)
        #expect(view.jumpBackStack.isEmpty && view.jumpForwardStack.isEmpty)
    }

    @Test(arguments: [Int.min, 0, 4, Int.max])
    func invalidPageNumbersStillClampAndExplainTheRange(pageNumber: Int) async {
        let (window, view) = makeReader()
        defer { close(window, view) }

        view.vimGoToPage(pageNumber)
        await nextTestMainQueueTurn()

        #expect(view.currentPage === view.document?.page(at: pageNumber < 1 ? 0 : 2))
        #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.pageNumberOutOfRange(3)))
    }

    @Test(arguments: [1, 2, 3])
    func validPageNumbersDoNotShowFeedback(pageNumber: Int) async {
        let (window, view) = makeReader()
        defer { close(window, view) }

        view.vimGoToPage(pageNumber)
        await nextTestMainQueueTurn()

        #expect(view.currentPage === view.document?.page(at: pageNumber - 1))
        #expect(currentToast(in: window) == nil)
    }

    private func makeReader() -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.goToFirstPage(nil)
        return (window, view)
    }

    private func currentToast(in window: NSWindow) -> ToastView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
    }

    private func close(_ window: NSWindow, _ view: VellumPDFView) {
        view.searchController?.clear()
        view.cancelPendingRestore()
        window.contentView = nil
        window.close()
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func enter(_ query: String, into field: NSTextField) {
        field.stringValue = query
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }
}

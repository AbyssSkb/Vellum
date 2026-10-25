@preconcurrency import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF quick open interaction")
struct PDFQuickOpenInteractionTests {
    @Test
    func emptyWindowSearchFocusAndEscapeRestoreTheOriginalResponder() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let field = try await fixture.readyField()
        #expect(!fixture.state.hasOpenTabs)
        #expect(fixture.state.hasBlockingReaderPresentation)
        let editor = try #require(field.currentEditor() as? NSTextView)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) == true)
        try await waitForTestCondition("Escape did not restore the empty window focus") {
            !fixture.state.isPDFQuickOpenPresented && fixture.window.firstResponder === fixture.originalFocus
        }
        #expect(!fixture.state.hasBlockingReaderPresentation)
        #expect(fixture.state.pdfQuickOpenSearch.results.isEmpty)
    }

    @Test
    func returnOpensThePDFAndReopeningReusesItsTab() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for _ in 0..<2 {
            let field = try await fixture.readyField()
            let editor = try #require(field.currentEditor() as? NSTextView)
            #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
            try await waitForTestCondition("Return did not open the chosen PDF") {
                !fixture.state.isPDFQuickOpenPresented && fixture.state.selectedTab?.url == fixture.pdfURL
            }
            #expect(fixture.state.tabs.count == 1)
            #expect(fixture.state.selectedTab?.document?.pageCount == 1)
            await nextTestMainQueueTurn()
            fixture.state.showPDFQuickOpen()
        }
    }

    @Test
    func returnWithNoResultsKeepsSearchOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let field = try await fixture.readyField()
        let editor = try #require(field.currentEditor() as? NSTextView)
        field.stringValue = "no-matching-document"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await waitForTestCondition("Search did not finish") { !fixture.state.pdfQuickOpenSearch.isSearching }
        #expect(fixture.state.pdfQuickOpenSearch.results.isEmpty)
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        await nextTestMainQueueTurn()
        #expect(fixture.state.isPDFQuickOpenPresented)
        #expect(!fixture.state.hasOpenTabs)
    }

    private struct Presentation: View {
        @ObservedObject var state: AppState
        var body: some View {
            if state.isPDFQuickOpenPresented {
                PDFQuickOpenOverlay(search: state.pdfQuickOpenSearch).environmentObject(state)
            } else {
                Color.clear
            }
        }
    }

    private final class FocusWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private final class FocusView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor
    private final class Fixture {
        let preferences: TestPreferences
        let directory: URL
        let pdfURL: URL
        let state: AppState
        let window: NSWindow
        let originalFocus = FocusView(frame: .zero)
        let host: NSHostingView<AnyView>

        init() throws {
            _ = NSApplication.shared
            preferences = try TestPreferences()
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            pdfURL = directory.appendingPathComponent("Quick open 中文.pdf")
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: 0)
            try #require(document.write(to: pdfURL))
            state = AppState(sessionDefaults: preferences.defaults, keyboardController: KeyboardController(
                installsKeyMonitor: false, installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
            ), pdfQuickOpenSearch: PDFQuickOpenSearch(executableURL: URL(fileURLWithPath: "/usr/bin/true"), initialPaths: [pdfURL]))
            window = FocusWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(originalFocus)
            state.readerWindow = window
            #expect(window.makeFirstResponder(originalFocus))
            host = NSHostingView(rootView: AnyView(Presentation(state: state)))
            host.frame = window.contentView?.bounds ?? .zero
            window.contentView?.addSubview(host)
            state.showPDFQuickOpen()
            host.layoutSubtreeIfNeeded()
        }

        private func searchField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { self.searchField(in: $0) }.first
        }

        func readyField() async throws -> NSTextField {
            try await waitForTestCondition("Quick open search did not receive focus") {
                guard let field = searchField(in: host), let editor = field.currentEditor() else { return false }
                return window.firstResponder === editor
            }
            return try #require(searchField(in: host))
        }

        func close() {
            state.hidePDFQuickOpen()
            state.keyboardController.cancelInput()
            state.readerWindow = nil
            host.rootView = AnyView(EmptyView())
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
            preferences.cleanup()
        }
    }
}

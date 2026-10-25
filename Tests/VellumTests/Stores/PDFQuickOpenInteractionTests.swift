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

    @Test
    func typingKeepsTheSearchFieldAndResultsAreaStable() async throws {
        let fixture = try Fixture(candidateCount: 12, matchingScript: "/bin/sleep 0.3\n/bin/cat >/dev/null\nexit 1")
        defer { fixture.close() }
        let field = try await fixture.readyField()
        let editor = try #require(field.currentEditor() as? NSTextView)
        fixture.host.layoutSubtreeIfNeeded()
        let fieldFrame = field.convert(field.bounds, to: nil)
        let scrollView = try #require(fixture.resultsScrollView())
        let resultsHeight = scrollView.bounds.height

        editor.insertText("D", replacementRange: editor.selectedRange())
        try await waitForTestCondition("Typing did not start matching") {
            fixture.state.pdfQuickOpenSearch.query == "D" && fixture.state.pdfQuickOpenSearch.isSearching
        }
        await nextTestMainQueueTurn()
        fixture.host.layoutSubtreeIfNeeded()
        #expect(field.convert(field.bounds, to: nil) == fieldFrame)
        #expect(scrollView.bounds.height == resultsHeight)
        #expect(fixture.window.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 1, length: 0))
        #expect(try await fixture.readyField() === field)

        try await waitForTestCondition("Matching did not finish") { !fixture.state.pdfQuickOpenSearch.isSearching }
        await nextTestMainQueueTurn()
        fixture.host.layoutSubtreeIfNeeded()
        #expect(fixture.state.pdfQuickOpenSearch.results.isEmpty)
        #expect(field.convert(field.bounds, to: nil) == fieldFrame)
        #expect(scrollView.bounds.height == resultsHeight)
        #expect(fixture.window.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 1, length: 0))

        editor.setMarkedText("深", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        await nextTestMainQueueTurn()
        fixture.host.layoutSubtreeIfNeeded()
        #expect(editor.hasMarkedText())
        #expect(fixture.window.firstResponder === editor)
        for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            #expect(field.delegate?.control?(field, textView: editor, doCommandBy: selector) == false)
        }
        #expect(fixture.state.isPDFQuickOpenPresented)
        editor.unmarkText()
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

        init(candidateCount: Int = 1, matchingScript: String? = nil) throws {
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
            let executableURL: URL
            if let matchingScript {
                executableURL = directory.appendingPathComponent("fzf")
                try ("#!/bin/sh\n" + matchingScript + "\n").write(to: executableURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
            } else {
                executableURL = URL(fileURLWithPath: "/usr/bin/true")
            }
            let paths = [pdfURL] + (1..<candidateCount).map { [directory] in directory.appendingPathComponent("Paper \($0).pdf") }
            state = AppState(sessionDefaults: preferences.defaults, keyboardController: KeyboardController(
                installsKeyMonitor: false, installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
            ), pdfQuickOpenSearch: PDFQuickOpenSearch(executableURL: executableURL, initialPaths: paths))
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

        func resultsScrollView() -> NSScrollView? {
            func find(in view: NSView) -> NSScrollView? {
                if let scrollView = view as? NSScrollView { return scrollView }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return find(in: host)
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

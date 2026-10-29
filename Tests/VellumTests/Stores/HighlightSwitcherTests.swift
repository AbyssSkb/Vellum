@preconcurrency import AppKit
@preconcurrency import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Highlight switcher")
struct HighlightSwitcherTests {
    @Test
    func emptyListShowsWarningWithoutChangingFocus() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.state.handleVimCommand(.showHighlights)

        #expect(fixture.state.highlightItems.isEmpty)
        #expect(!fixture.state.isHighlightsPresented)
        #expect(!fixture.state.hasBlockingReaderPresentation)
        #expect(fixture.window.firstResponder === fixture.reader)
        let toast = fixture.window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
        #expect(toast?.message == AppUILanguage.saved().text(.noHighlightsInFile))
        #expect(toast?.kind == .warning)
    }

    @Test
    func escapeRestoresOriginalFocus() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let selection = try #require(fixture.reader.document?.findString("Alpha", withOptions: []).first)
        _ = fixture.reader.addHighlightAnnotations(for: selection, color: .yellow)
        #expect(fixture.window.makeFirstResponder(fixture.editor))
        let field = try await fixture.show()
        #expect(fixture.state.highlightItems.count == 1)
        #expect(fixture.state.hasBlockingReaderPresentation)

        #expect(field.performCommand(#selector(NSResponder.cancelOperation(_:))))
        #expect(!fixture.state.isHighlightsPresented)
        #expect(!fixture.state.hasBlockingReaderPresentation)
        try await waitForTestCondition("Escape did not restore the original responder") {
            fixture.window.firstResponder === fixture.editor
        }
    }

    @Test
    func filteredEnterSelectsHighlightedTextAndReturnsToReader() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for text in ["Alpha", "Beta"] {
            let selection = try #require(fixture.reader.document?.findString(text, withOptions: []).first)
            _ = fixture.reader.addHighlightAnnotations(for: selection, color: .yellow)
        }
        let field = try await fixture.show()
        #expect(fixture.state.highlightItems.count == 2)
        field.stringValue = "beta"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        fixture.host.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()
        await nextTestMainQueueTurn()

        #expect(field.performCommand(#selector(NSResponder.insertNewline(_:))))
        #expect(!fixture.state.isHighlightsPresented)
        #expect(fixture.state.highlightItems.isEmpty)
        #expect(fixture.reader.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) == "Beta")
        try await waitForTestCondition("Opening a highlight did not focus the reader") {
            fixture.window.firstResponder === fixture.reader
        }
    }

    @Test
    func readerChangeClosesListAndRejectsStaleSelection() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let selection = try #require(fixture.reader.document?.findString("Alpha", withOptions: []).first)
        _ = fixture.reader.addHighlightAnnotations(for: selection, color: .yellow)
        fixture.state.showHighlights()
        let item = try #require(fixture.state.highlightItems.first)

        fixture.state.prepareForSelectedReaderChange()
        #expect(!fixture.state.isHighlightsPresented)
        #expect(fixture.state.highlightItems.isEmpty)
        fixture.state.openHighlight(item)
        #expect(fixture.reader.currentSelection == nil)
    }

    private final class FocusTestWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @MainActor
    private final class Fixture {
        let preferences: TestPreferences
        let state: AppState
        let reader = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window: NSWindow

        init() throws {
            _ = NSApplication.shared
            preferences = try TestPreferences()
            state = makeTestAppState(defaults: preferences.defaults)
            let document = try makeTextPDF(pages: [[("Alpha", NSPoint(x: 50, y: 700)),
                                                    ("Beta", NSPoint(x: 50, y: 650))]])
            let tab = PDFTab(url: nil, document: document)
            _ = state.tabStore.openInNewTabs([tab])
            reader.document = document
            reader.appState = state
            window = FocusTestWindow(contentRect: reader.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(reader)
            window.contentView?.addSubview(editor)
            host.frame = reader.frame
            window.contentView?.addSubview(host)
            state.readerWindow = window
            state.setActiveReaderController(reader, for: tab.id)
            window.orderFront(nil)
            reader.layoutDocumentView()
        }

        func show() async throws -> ListSearchTextField {
            state.showHighlights()
            host.rootView = AnyView(HighlightSwitcherOverlay().environmentObject(state))
            host.layoutSubtreeIfNeeded()
            func fields(in view: NSView) -> [ListSearchTextField] {
                (view as? ListSearchTextField).map { [$0] } ?? view.subviews.flatMap(fields)
            }
            let field = try #require(fields(in: host).first)
            try await waitForTestCondition("Highlight search did not receive initial focus") {
                field.currentEditor().map { self.window.firstResponder === $0 } == true
            }
            return field
        }

        func close() {
            state.keyboardController.cancelInput()
            state.activeReaderController = nil
            state.readerWindow = nil
            reader.searchController?.clear()
            reader.cancelPendingRestore()
            reader.stopScrollAnimation()
            reader.stopZoomState()
            reader.readerStateSaveWorkItem?.cancel()
            reader.readingPositionReportWorkItem?.cancel()
            reader.appState = nil
            window.makeFirstResponder(nil)
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            window.close()
            preferences.cleanup()
        }
    }
}

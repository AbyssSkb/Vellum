@preconcurrency import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Tab switcher interaction")
struct TabSwitcherInteractionTests {
    @Test
    func candidateNavigationKeepsTheReaderUntilReturnCommits() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let field = try await fixture.readySearchField()
        let editor = try #require(field.currentEditor() as? NSTextView)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))) == true)
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))) == true)
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))) == true)
        await fixture.drainUpdates()
        #expect(fixture.state.selectedTabID == fixture.tabs[0].id)
        #expect(fixture.state.isTabSwitcherPresented)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        try await waitForTestCondition("Return did not commit and dismiss the switcher") {
            fixture.state.selectedTabID == fixture.tabs[1].id && !fixture.state.isTabSwitcherPresented
        }
        #expect(fixture.state.selectedTabID == fixture.tabs[1].id)
        #expect(!fixture.state.isTabSwitcherPresented)
    }

    @Test
    func noMatchingSearchReturnStaysOpenAndEscapeRestoresOriginalFocus() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let field = try await fixture.readySearchField()
        let editor = try #require(field.currentEditor() as? NSTextView)
        field.stringValue = "a-title-with-no-matching-tab"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        await fixture.drainUpdates()

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        // Observe beyond the 150 ms dismissal so Escape cannot mask an erroneous Return close.
        try await Task.sleep(for: .milliseconds(180))
        await fixture.drainUpdates()
        #expect(fixture.state.isTabSwitcherPresented)
        #expect(fixture.state.selectedTabID == fixture.tabs[0].id)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) == true)
        try await waitForTestCondition("Escape did not dismiss the switcher and restore focus") {
            !fixture.state.isTabSwitcherPresented && fixture.window.firstResponder === fixture.originalFocus
        }
        #expect(!fixture.state.isTabSwitcherPresented)
        #expect(fixture.state.selectedTabID == fixture.tabs[0].id)
        let restoredFocus = fixture.window.firstResponder === fixture.originalFocus
        #expect(restoredFocus)
    }

    @Test
    func externalFileSelectionDismissesTheSwitcherAndFocusesTheNewReader() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let field = try await fixture.readySearchField()
        let nextTab = fixture.tabs[1]
        let nextReader = VellumPDFView(frame: fixture.host.frame)
        nextReader.appState = fixture.state
        nextReader.document = nextTab.document
        fixture.window.contentView?.addSubview(nextReader)

        fixture.state.selectTab(nextTab.id)
        fixture.state.setActiveReaderController(nextReader, for: nextTab.id)
        await fixture.drainUpdates()
        try await waitForTestCondition("External selection did not release the field and focus the new reader") {
            !fixture.state.isTabSwitcherPresented && field.window == nil
                && fixture.window.firstResponder === nextReader
        }

        #expect(fixture.state.selectedTabID == nextTab.id)
        #expect(!fixture.state.isTabSwitcherPresented)
        #expect(fixture.state.responderBeforeSwitcher == nil)
        #expect(field.window == nil)
        let newReaderHasFocus = fixture.window.firstResponder === nextReader
        #expect(newReaderHasFocus)
    }

    @Test
    func closingTheLastFileDismissesTheSwitcherAndReleasesItsFieldEditor() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = try await fixture.readySearchField()
        fixture.state.closeTab(fixture.tabs[1].id)
        let field = try await fixture.readySearchField()
        let editor = try #require(field.currentEditor())
        #expect(fixture.state.isTabSwitcherPresented)

        fixture.state.closeSelectedTab()
        await fixture.drainUpdates()
        try await waitForTestCondition("Closing the last file did not release the switcher editor") {
            !fixture.state.isTabSwitcherPresented && field.window == nil
                && fixture.window.firstResponder !== editor
        }

        #expect(!fixture.state.hasOpenTabs)
        #expect(!fixture.state.isTabSwitcherPresented)
        #expect(fixture.state.responderBeforeSwitcher == nil)
        #expect(field.window == nil)
        let releasedFocus = fixture.window.firstResponder !== editor
        #expect(releasedFocus)
    }

    private struct Presentation: View {
        @ObservedObject var state: AppState
        var body: some View {
            if state.isTabSwitcherPresented {
                TabSwitcherOverlay().environmentObject(state)
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
        let state: AppState
        let tabs: [PDFTab]
        let window: NSWindow
        let originalFocus = FocusView(frame: .zero)
        let host: NSHostingView<AnyView>

        init() throws {
            _ = NSApplication.shared
            preferences = try TestPreferences()
            state = makeTestAppState(defaults: preferences.defaults)
            tabs = ["first", "second"].map { name in
                let document = PDFDocument()
                let page = PDFPage()
                page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
                document.insert(page, at: 0)
                return PDFTab(url: URL(fileURLWithPath: "/tmp/\(name).pdf"), document: document, snapshot: .initial)
            }
            _ = state.tabStore.openInNewTabs(tabs)
            _ = state.tabStore.selectTab(tabs[0].id)
            window = FocusWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(originalFocus)
            state.readerWindow = window
            #expect(window.makeFirstResponder(originalFocus))
            state.showTabSwitcher()
            host = NSHostingView(rootView: AnyView(Presentation(state: state)))
            host.frame = window.contentView?.bounds ?? .zero
            window.contentView?.addSubview(host)
            host.layoutSubtreeIfNeeded()
        }

        private func searchField() -> NSTextField? {
            func fields(in view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
            }
            return fields(in: host).first { $0.isEditable }
        }

        func readySearchField() async throws -> NSTextField {
            try await waitForTestCondition("The tab switcher search field did not receive focus") {
                guard let field = searchField(), let editor = field.currentEditor() else { return false }
                return window.firstResponder === editor
            }
            return try #require(searchField())
        }

        func drainUpdates() async {
            host.layoutSubtreeIfNeeded()
            // Focus restoration can enqueue a follow-up request on the main queue.
            await nextTestMainQueueTurn()
            await nextTestMainQueueTurn()
        }

        func close() {
            state.keyboardController.cancelInput()
            state.activeReaderController = nil
            state.readerWindow = nil
            for reader in window.contentView?.subviews.compactMap({ $0 as? VellumPDFView }) ?? [] {
                reader.cancelPendingRestore()
                reader.stopScrollAnimation()
                reader.stopZoomState()
                reader.readerStateSaveWorkItem?.cancel()
                reader.readingPositionReportWorkItem?.cancel()
                reader.appState = nil
            }
            host.rootView = AnyView(EmptyView())
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
            preferences.cleanup()
        }
    }
}

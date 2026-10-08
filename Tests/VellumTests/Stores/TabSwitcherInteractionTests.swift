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
        try await Task.sleep(for: .milliseconds(100))
        let field = try fixture.searchField()
        let editor = try #require(field.currentEditor() as? NSTextView)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))) == true)
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))) == true)
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))) == true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(fixture.state.selectedTabID == fixture.tabs[0].id)
        #expect(fixture.state.isTabSwitcherPresented)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.state.selectedTabID == fixture.tabs[1].id)
        #expect(!fixture.state.isTabSwitcherPresented)
    }

    @Test
    func noMatchingSearchReturnStaysOpenAndEscapeRestoresOriginalFocus() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await Task.sleep(for: .milliseconds(100))
        let field = try fixture.searchField()
        let editor = try #require(field.currentEditor() as? NSTextView)
        field.stringValue = "a-title-with-no-matching-tab"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await Task.sleep(for: .milliseconds(80))

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        try await Task.sleep(for: .milliseconds(180))
        #expect(fixture.state.isTabSwitcherPresented)
        #expect(fixture.state.selectedTabID == fixture.tabs[0].id)

        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) == true)
        let deadline = ContinuousClock.now + .seconds(2)
        while fixture.state.isTabSwitcherPresented || fixture.window.firstResponder !== fixture.originalFocus {
            guard ContinuousClock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(20))
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
        try await Task.sleep(for: .milliseconds(100))
        let field = try fixture.searchField()
        let nextTab = fixture.tabs[1]
        let nextReader = VellumPDFView(frame: fixture.host.frame)
        nextReader.appState = fixture.state
        nextReader.document = nextTab.document
        fixture.window.contentView?.addSubview(nextReader)

        fixture.state.selectTab(nextTab.id)
        fixture.state.setActiveReaderController(nextReader, for: nextTab.id)
        try await Task.sleep(for: .milliseconds(250))

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
        try await Task.sleep(for: .milliseconds(100))
        fixture.state.closeTab(fixture.tabs[1].id)
        try await Task.sleep(for: .milliseconds(80))
        let field = try fixture.searchField()
        let editor = try #require(field.currentEditor())
        #expect(fixture.state.isTabSwitcherPresented)

        fixture.state.closeSelectedTab()
        try await Task.sleep(for: .milliseconds(100))

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
        let suite = "Vellum.TabSwitcherInteraction.\(UUID().uuidString)"
        let defaults: UserDefaults
        let state: AppState
        let tabs: [PDFTab]
        let window: NSWindow
        let originalFocus = FocusView(frame: .zero)
        let host: NSHostingView<AnyView>

        init() throws {
            _ = NSApplication.shared
            defaults = try #require(UserDefaults(suiteName: suite))
            state = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
                installsKeyMonitor: false, installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
            ))
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

        func searchField() throws -> NSTextField {
            func fields(in view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
            }
            return try #require(fields(in: host).first { $0.isEditable })
        }

        func close() {
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}

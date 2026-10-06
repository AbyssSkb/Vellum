@preconcurrency import AppKit
@preconcurrency import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Reader focus ownership")
struct ReaderFocusTests {
    @Test
    func closingThenReopeningOutlineCancelsQueuedReaderFocus() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await settle()
        let outline = try fixture.outline()
        #expect(fixture.window.makeFirstResponder(outline))
        fixture.state.toggleOutlineSidebar()
        fixture.state.toggleOutlineSidebar()
        try await settle()
        #expect(fixture.state.isOutlineVisible)
        fixture.expectFocus(outline)
    }

    enum FocusInterruption: CaseIterable { case field, editor, switcher, document, tab }

    @Test(arguments: FocusInterruption.allCases, [false, true])
    func queuedFocusCannotOverrideNewerOwnership(interruption: FocusInterruption, activePane: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await settle()
        fixture.state.isOutlineVisible = false
        let outline = try fixture.outline()
        #expect(fixture.window.makeFirstResponder(outline))
        if activePane { fixture.state.focusActiveReaderSoon() } else { fixture.state.focusReaderSoon() }
        let expected: NSResponder
        switch interruption {
        case .field:
            #expect(fixture.window.makeFirstResponder(fixture.field))
            expected = try #require(fixture.field.currentEditor())
        case .editor:
            #expect(fixture.window.makeFirstResponder(fixture.editor))
            expected = fixture.editor
        case .switcher:
            fixture.state.showTabSwitcher()
            #expect(fixture.window.makeFirstResponder(fixture.field))
            expected = try #require(fixture.field.currentEditor())
        case .document:
            fixture.state.tabStore.replaceDocument(for: fixture.tab.id, with: Fixture.document())
            expected = outline
        case .tab:
            _ = fixture.state.tabStore.openInNewTabs([PDFTab(url: nil, document: Fixture.document())])
            expected = outline
        }
        try await settle()
        fixture.expectFocus(expected)
    }

    @Test
    func switcherRestoresItsActualPaneAndLeavesNewFocusAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await settle()
        let outline = try fixture.outline()
        for origin in [fixture.reader as NSView, outline] {
            #expect(fixture.window.makeFirstResponder(origin))
            fixture.state.showTabSwitcher()
            #expect(fixture.window.makeFirstResponder(fixture.field))
            fixture.state.hideTabSwitcher()
            try await settle()
            fixture.expectFocus(origin)
        }

        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.state.showTabSwitcher()
        #expect(fixture.window.makeFirstResponder(fixture.field))
        fixture.state.hideTabSwitcher()
        #expect(fixture.window.makeFirstResponder(fixture.editor))
        try await settle()
        fixture.expectFocus(fixture.editor)

        let secondTab = PDFTab(url: nil, document: Fixture.document())
        _ = fixture.state.tabStore.openInNewTabs([secondTab])
        _ = fixture.state.tabStore.selectTab(fixture.tab.id)
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.state.showTabSwitcher()
        #expect(fixture.window.makeFirstResponder(fixture.field))
        fixture.state.selectTabFromSwitcher(secondTab.id)
        fixture.host.rootView = AnyView(OutlineSidebar(tab: secondTab).environmentObject(fixture.state))
        let newReader = VellumPDFView(frame: fixture.reader.frame)
        newReader.appState = fixture.state
        newReader.document = secondTab.document
        fixture.window.contentView?.addSubview(newReader)
        fixture.state.setActiveReaderController(newReader, for: secondTab.id)
        try await settle()
        #expect(fixture.state.selectedTabID == secondTab.id)
        fixture.expectFocus(try fixture.outline())
    }

    @Test(arguments: ["g", "1"])
    func explicitlyResigningTheReaderClearsItsPendingCommand(prefix: String) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await settle()
        let outline = try fixture.outline()
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        #expect(fixture.state.handleKeyEvent(key(prefix, in: fixture.window)))
        #expect(fixture.window.makeFirstResponder(outline))
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        let generation = fixture.reader.restoreGeneration
        if prefix == "g" {
            #expect(fixture.state.handleKeyEvent(key("g", in: fixture.window)))
            #expect(fixture.reader.restoreGeneration == generation)
            #expect(fixture.state.handleKeyEvent(key("g", in: fixture.window)))
        } else {
            #expect(fixture.state.handleKeyEvent(key("G", in: fixture.window)))
            let isLastPage = fixture.reader.currentPage === fixture.tab.document?.page(at: 2)
            #expect(isLastPage)
        }
        #expect(fixture.reader.restoreGeneration > generation)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(60)) }

    private func key(_ value: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero,
                         modifierFlags: value == "G" ? .shift : [], timestamp: 0,
                         windowNumber: window.windowNumber, context: nil,
                         characters: value, charactersIgnoringModifiers: value,
                         isARepeat: false, keyCode: value == "1" ? 18 : 5)!
    }

    private final class FocusTestWindow: NSWindow {
        // SwiftPM does not own an active app window; keep only key ownership deterministic.
        override var isKeyWindow: Bool { true }
    }

    @MainActor
    private final class Fixture {
        let suite = "Vellum.ReaderFocus.\(UUID().uuidString)"
        let defaults: UserDefaults
        let state: AppState
        let window: NSWindow
        let tab: PDFTab
        let reader = VellumPDFView(frame: NSRect(x: 256, y: 0, width: 500, height: 400))
        let field = NSTextField(frame: NSRect(x: 280, y: 20, width: 180, height: 24))
        let editor = NSTextView(frame: NSRect(x: 280, y: 60, width: 180, height: 40))
        let host: NSHostingView<AnyView>

        init() throws {
            _ = NSApplication.shared
            defaults = try #require(UserDefaults(suiteName: suite))
            state = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
                installsKeyMonitor: false, installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
            ))
            tab = PDFTab(url: nil, document: Self.document())
            _ = state.tabStore.openInNewTabs([tab])
            state.isOutlineVisible = true
            reader.appState = state
            reader.document = tab.document
            host = NSHostingView(rootView: AnyView(OutlineSidebar(tab: tab).environmentObject(state)))
            host.frame = NSRect(x: 0, y: 0, width: 256, height: 400)
            window = FocusTestWindow(contentRect: NSRect(x: 0, y: 0, width: 756, height: 400),
                                     styleMask: .borderless, backing: .buffered, defer: false)
            window.title = "Vellum Reader Focus Regression"
            window.isReleasedWhenClosed = false
            for view in [reader as NSView, host, field, editor] { window.contentView?.addSubview(view) }
            state.readerWindow = window
            state.setActiveReaderController(reader, for: tab.id)
            window.orderFront(nil)
            #expect(window.isKeyWindow)
            host.layoutSubtreeIfNeeded()
            reader.layoutDocumentView()
        }

        func outline() throws -> PDFOutlineKeyView {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            return try #require(descendants(host).compactMap { $0 as? PDFOutlineKeyView }.first)
        }

        func expectFocus(_ responder: NSResponder) {
            let matches = window.firstResponder === responder
            #expect(matches)
        }

        static func document() -> PDFDocument {
            let document = PDFDocument()
            for index in 0..<3 {
                let page = PDFPage()
                page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
                document.insert(page, at: index)
            }
            return document
        }

        func close() {
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}

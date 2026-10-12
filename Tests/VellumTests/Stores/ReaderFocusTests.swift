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
        try await fixture.ready()
        let outline = try fixture.outline()
        #expect(fixture.window.makeFirstResponder(outline))
        fixture.state.toggleOutlineSidebar()
        fixture.state.toggleOutlineSidebar()
        try await fixture.drainQueuedFocus()
        #expect(fixture.state.isOutlineVisible)
        fixture.expectFocus(outline)
    }

    enum FocusInterruption: CaseIterable { case field, editor, switcher, document, tab }

    @Test(arguments: FocusInterruption.allCases, [false, true])
    func queuedFocusCannotOverrideNewerOwnership(interruption: FocusInterruption, activePane: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.ready()
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
        try await fixture.drainQueuedFocus()
        fixture.expectFocus(expected)
    }

    @Test
    func switcherRestoresItsActualPaneAndLeavesNewFocusAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        let outline = try fixture.outline()
        for origin in [fixture.reader as NSView, outline] {
            #expect(fixture.window.makeFirstResponder(origin))
            fixture.state.showTabSwitcher()
            #expect(fixture.window.makeFirstResponder(fixture.field))
            fixture.state.hideTabSwitcher()
            try await fixture.waitForFocus(origin)
            fixture.expectFocus(origin)
        }

        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.state.showTabSwitcher()
        #expect(fixture.window.makeFirstResponder(fixture.field))
        fixture.state.hideTabSwitcher()
        #expect(fixture.window.makeFirstResponder(fixture.editor))
        try await fixture.drainQueuedFocus()
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
        try await fixture.waitForFocus(newReader)
        #expect(fixture.state.selectedTabID == secondTab.id)
        fixture.expectFocus(newReader)
    }

    @Test
    func focusSwitchPreservesSidebarAndCannotBeOverriddenByAnOlderRequest() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        let outline = try fixture.outline()
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.state.switchReadingFocus()
        try await fixture.waitForFocus(outline)
        fixture.expectFocus(outline)
        fixture.state.switchReadingFocus()
        try await fixture.waitForFocus(fixture.reader)
        fixture.expectFocus(fixture.reader)
        #expect(fixture.state.isOutlineVisible)

        fixture.state.focusOutlineSidebar()
        fixture.reader.focus()
        try await fixture.drainQueuedFocus()
        fixture.expectFocus(fixture.reader)
        #expect(fixture.state.isOutlineVisible)
    }

    @Test(arguments: [false, true])
    func switchingFilesPreservesTheFocusedPane(outlineFocused: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        let outline = try fixture.outline()
        #expect(fixture.window.makeFirstResponder(outlineFocused ? outline : fixture.reader))
        let nextTab = PDFTab(url: nil, document: Fixture.document())
        _ = fixture.state.tabStore.openInNewTabs([nextTab])
        fixture.state.prepareForSelectedReaderChange()
        fixture.host.rootView = AnyView(OutlineSidebar(tab: nextTab).environmentObject(fixture.state))
        let nextReader = VellumPDFView(frame: fixture.reader.frame)
        nextReader.appState = fixture.state
        nextReader.document = nextTab.document
        fixture.window.contentView?.addSubview(nextReader)
        fixture.state.setActiveReaderController(nextReader, for: nextTab.id)
        try await fixture.drainQueuedFocus()
        let expected = outlineFocused ? try fixture.outline() : nextReader
        try await fixture.waitForFocus(expected)
        fixture.expectFocus(expected)
    }

    @Test
    func reactivatingACachedReaderReportsItsPositionWithoutLayoutOrMovement() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        fixture.reader.vimGoToPage(3)
        await nextTestMainQueueTurn()
        try await waitForTestCondition("The reader did not reach the third page") {
            fixture.reader.readingDestination()?.page === fixture.tab.document?.page(at: 2)
        }
        let expected = try #require(fixture.reader.readingDestination())
        #expect(expected.page === fixture.tab.document?.page(at: 2))

        let nextTab = PDFTab(url: nil, document: Fixture.document())
        _ = fixture.state.tabStore.openInNewTabs([nextTab])
        fixture.state.prepareForSelectedReaderChange()
        try await fixture.drainQueuedFocus()
        _ = fixture.state.tabStore.selectTab(fixture.tab.id)
        fixture.state.prepareForSelectedReaderChange()
        #expect(fixture.state.outlineReadingDestination == nil)
        fixture.reader.readingPositionReportWorkItem?.cancel()
        fixture.reader.readingPositionReportWorkItem = nil

        fixture.state.setActiveReaderController(fixture.reader, for: fixture.tab.id)
        try await waitForTestCondition("The cached reader did not report its position") {
            fixture.state.outlineReadingDestination?.page === expected.page
                && fixture.state.outlineReadingDestination?.point == expected.point
        }
        let reported = try #require(fixture.state.outlineReadingDestination)
        #expect(reported.page === expected.page)
        #expect(reported.point == expected.point)
    }

    @Test
    func onlyActiveReadingMovementClearsTheExplicitSection() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let page = try #require(fixture.tab.document?.page(at: 0))
        let destination = PDFDestination(page: page, at: NSPoint(x: 40, y: 500))
        fixture.state.outlineReadingItemID = "section"
        fixture.state.updateOutlineReadingPosition(destination, from: fixture.reader)
        #expect(fixture.state.outlineReadingItemID == "section")
        let staleReader = VellumPDFView()
        fixture.state.updateOutlineReadingPosition(destination, from: staleReader, userNavigated: true)
        #expect(fixture.state.outlineReadingItemID == "section")
        fixture.state.updateOutlineReadingPosition(destination, from: fixture.reader, userNavigated: true)
        #expect(fixture.state.outlineReadingItemID == nil)
    }

    @Test(arguments: ["g", "1"])
    func explicitlyResigningTheReaderClearsItsPendingCommand(prefix: String) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.ready()
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
        let preferences: TestPreferences
        let state: AppState
        let window: NSWindow
        let tab: PDFTab
        let reader = VellumPDFView(frame: NSRect(x: 256, y: 0, width: 500, height: 400))
        let field = NSTextField(frame: NSRect(x: 280, y: 20, width: 180, height: 24))
        let editor = NSTextView(frame: NSRect(x: 280, y: 60, width: 180, height: 40))
        let host: NSHostingView<AnyView>

        init() throws {
            _ = NSApplication.shared
            preferences = try TestPreferences()
            state = makeTestAppState(defaults: preferences.defaults)
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

        func ready() async throws {
            try await waitForTestCondition("The outline and reader did not mount") {
                state.activeOutlineView?.window === window && reader.currentPage != nil
            }
            try await drainQueuedFocus()
        }

        func waitForFocus(_ responder: NSResponder) async throws {
            try await waitForTestCondition("The requested pane did not receive focus") {
                window.firstResponder === responder
            }
            try await drainQueuedFocus()
        }

        func drainQueuedFocus() async throws {
            host.layoutSubtreeIfNeeded()
            try await waitForTestCondition("The outline did not receive the latest focus intent") {
                (state.activeOutlineView?.delegate as? PDFOutlineView.Coordinator)?.lastFocusGeneration
                    == state.outlineFocusGeneration
            }
            // Active-pane restoration can enqueue a second reader-focus request.
            await nextTestMainQueueTurn()
            await nextTestMainQueueTurn()
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
            state.keyboardController.cancelInput()
            state.activeOutlineView?.cancelPendingFocus()
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
            window.makeFirstResponder(nil)
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            window.close()
            preferences.cleanup()
        }
    }
}

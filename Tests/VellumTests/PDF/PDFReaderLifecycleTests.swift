import AppKit
import Combine
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reader teardown")
struct PDFReaderLifecycleTests {
    @Test(arguments: [false, true])
    func dismantleDefersPublicationAndSavesFinalSnapshot(updated: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let reader = try await fixture.mountedReader()
        if updated {
            fixture.host.rootView = fixture.readerContent(snapshot: .initial)
            fixture.host.layoutSubtreeIfNeeded()
            await nextMainQueueTurn()
        }
        reader.cancelPendingRestore()
        reader.autoScales = false
        reader.scaleFactor = 1.37
        reader.layoutDocumentView()
        reader.readerStateSaveWorkItem?.cancel()
        let save = try #require(reader.saveBeforeDismantle)
        var dismantling = false
        var dismantled = false
        var publicationsDuringDismantle = 0
        var finalSnapshot: ReaderSnapshot?
        let observation = fixture.state.objectWillChange.sink {
            if dismantling { publicationsDuringDismantle += 1 }
        }
        defer { observation.cancel() }
        reader.saveBeforeDismantle = { [weak reader] in
            reader?.saveBeforeDismantle = nil
            dismantling = true
            finalSnapshot = reader?.snapshot()
            save()
            dismantling = false
            dismantled = true
        }

        fixture.host.rootView = AnyView(EmptyView())
        fixture.host.layoutSubtreeIfNeeded()
        try await waitUntil { dismantled }
        #expect(publicationsDuringDismantle == 0)
        try #require(finalSnapshot?.scaleFactor == 1.37)
        await nextMainQueueTurn()

        #expect(reader.window == nil)
        #expect(fixture.state.tabs.first?.snapshot == finalSnapshot)
        #expect(AppSessionPersistence.load(defaults: fixture.defaults)?.tabs.first?.snapshot == finalSnapshot)
    }

    @Test(arguments: [false, true])
    func queuedSaveIgnoresRemovedTabOrReplacedDocument(replaced: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let reader = try await fixture.mountedReader()
        reader.cancelPendingRestore()
        reader.autoScales = false
        reader.scaleFactor = 1.37
        reader.readerStateSaveWorkItem?.cancel()
        let save = try #require(reader.saveBeforeDismantle)
        var dismantled = false
        var changingTab = false
        var snapshotPublications = 0
        let observation = fixture.state.$tabStore.dropFirst().sink { _ in
            if !changingTab { snapshotPublications += 1 }
        }
        defer { observation.cancel() }
        reader.saveBeforeDismantle = { [weak reader] in
            reader?.saveBeforeDismantle = nil
            save()
            changingTab = true
            if replaced {
                fixture.state.tabStore.replaceDocument(for: fixture.tab.id, with: PDFDocument())
            } else {
                _ = fixture.state.tabStore.closeTab(fixture.tab.id)
            }
            changingTab = false
            dismantled = true
        }

        fixture.host.rootView = AnyView(EmptyView())
        fixture.host.layoutSubtreeIfNeeded()
        try await waitUntil { dismantled }
        await nextMainQueueTurn()

        #expect(snapshotPublications == 0)
        if replaced {
            #expect(fixture.state.tabs.first?.snapshot == .initial)
        } else {
            #expect(fixture.state.tabs.isEmpty)
        }
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @MainActor
    private struct Fixture {
        let suiteName = "Vellum.ReaderTeardown.\(UUID().uuidString)"
        let defaults: UserDefaults
        let state: AppState
        let tab: PDFTab
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init() throws {
            _ = NSApplication.shared
            defaults = try #require(UserDefaults(suiteName: suiteName))
            state = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
                installsKeyMonitor: false, installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
            ))
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 1_600), for: .mediaBox)
            document.insert(page, at: 0)
            tab = PDFTab(url: URL(fileURLWithPath: "/tmp/reader-teardown.pdf"),
                         document: document, snapshot: .initial)
            _ = state.tabStore.openInNewTabs([tab])
            host = NSHostingView(rootView: AnyView(PDFReader(
                tabID: tab.id, document: document, snapshot: nil, isActive: true
            ).environmentObject(state)))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host.frame = window.contentView!.bounds
            window.contentView = host
            host.layoutSubtreeIfNeeded()
        }

        func readerContent(snapshot: ReaderSnapshot?) -> AnyView {
            AnyView(PDFReader(tabID: tab.id, document: tab.document!, snapshot: snapshot, isActive: true)
                .environmentObject(state))
        }

        func mountedReader() async throws -> VellumPDFView {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while state.activeReaderController == nil, ContinuousClock.now < deadline {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            return try #require(state.activeReaderController as? VellumPDFView)
        }

        func cleanUp() {
            host.rootView = AnyView(EmptyView())
            window.close()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

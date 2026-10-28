import AppKit
import Combine
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reader teardown")
struct PDFReaderLifecycleTests {
    @Test(arguments: [1, 2])
    func closeCommandReleasesMountedReadersAfterRepeatedOpening(tabCount: Int) async throws {
        let fixture = try CloseCommandFixture(tabCount: tabCount)
        defer { fixture.cleanUp() }

        for _ in 0..<8 {
            autoreleasepool {
                fixture.state.openInNewTabs(urls: fixture.urls)
            }
            for remainingCount in stride(from: tabCount, through: 1, by: -1) {
                try await waitForTestCondition("Selected reader mounted before closing", dispatchAppKitEvents: true) {
                    fixture.host.layoutSubtreeIfNeeded()
                    return (fixture.state.activeReaderController as? VellumPDFView)?.window === fixture.window
                }
                weak var closingReader: VellumPDFView?
                try autoreleasepool {
                    let reader = try #require(fixture.state.activeReaderController as? VellumPDFView)
                    closingReader = reader
                    #expect((reader.document?.pageCount ?? 0) > 1)
                    reader.layoutDocumentView()
                    fixture.window.displayIfNeeded()
                }

                autoreleasepool {
                    fixture.state.handleVimCommand(.closeTab)
                    fixture.host.layoutSubtreeIfNeeded()
                }
                #expect(fixture.state.tabs.count == remainingCount - 1)
                try await waitForTestCondition("Closed reader detached from its window", dispatchAppKitEvents: true) {
                    autoreleasepool {
                        fixture.host.layoutSubtreeIfNeeded()
                        return closingReader?.window == nil
                    }
                }
                try await waitForTestCondition("Closed reader finally deallocated", dispatchAppKitEvents: true) {
                    autoreleasepool { closingReader == nil }
                }
                await nextTestMainQueueTurn()
            }
            #expect(fixture.state.activeReaderController == nil)
        }
    }

    @Test
    func closeCommandReleasesReaderWithRealDocument() async throws {
        let fixture = try CloseCommandFixture(tabCount: 1, useRealDocument: true)
        defer { fixture.cleanUp() }
        fixture.state.openInNewTabs(urls: fixture.urls)
        try await waitForTestCondition("Real document reader mounted", dispatchAppKitEvents: true) {
            fixture.host.layoutSubtreeIfNeeded()
            return (fixture.state.activeReaderController as? VellumPDFView)?.window === fixture.window
        }
        weak var closingReader: VellumPDFView?
        try autoreleasepool {
            let reader = try #require(fixture.state.activeReaderController as? VellumPDFView)
            closingReader = reader
            #expect((reader.document?.pageCount ?? 0) > 1)
            reader.layoutDocumentView()
            fixture.window.displayIfNeeded()
        }
        autoreleasepool {
            fixture.state.handleVimCommand(.closeTab)
            fixture.host.layoutSubtreeIfNeeded()
        }
        #expect(fixture.state.tabs.isEmpty)
        try await waitForTestCondition("Real document reader detached", dispatchAppKitEvents: true) {
            fixture.host.layoutSubtreeIfNeeded()
            return closingReader?.window == nil
        }
        #expect(fixture.window.isVisible)
        try await waitForTestCondition("Real document reader finally deallocated", timeout: .seconds(60), dispatchAppKitEvents: true) {
            autoreleasepool { closingReader == nil }
        }
        #expect(fixture.window.isVisible)
    }

    @Test(arguments: [false, true])
    func dismantleDefersPublicationAndSavesFinalSnapshot(updated: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let reader = try await fixture.mountedReader()
        if updated {
            fixture.host.rootView = fixture.readerContent(snapshot: .initial)
            fixture.host.layoutSubtreeIfNeeded()
            await nextTestMainQueueTurn()
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
        try await waitForTestCondition("Reader dismantled") { dismantled }
        #expect(publicationsDuringDismantle == 0)
        try #require(finalSnapshot?.scaleFactor == 1.37)
        await nextTestMainQueueTurn()

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
        try await waitForTestCondition("Reader dismantled before tab change") { dismantled }
        await nextTestMainQueueTurn()

        #expect(snapshotPublications == 0)
        if replaced {
            #expect(fixture.state.tabs.first?.snapshot == .initial)
        } else {
            #expect(fixture.state.tabs.isEmpty)
        }
    }

    @MainActor
    private struct Fixture {
        let preferences: TestPreferences
        var defaults: UserDefaults { preferences.defaults }
        let state: AppState
        let tab: PDFTab
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init() throws {
            _ = NSApplication.shared
            preferences = try TestPreferences()
            state = makeTestAppState(defaults: preferences.defaults)
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
            try await waitForTestCondition("Reader mounted in SwiftUI host") {
                host.layoutSubtreeIfNeeded()
                return state.activeReaderController != nil
            }
            return try #require(state.activeReaderController as? VellumPDFView)
        }

        func cleanUp() {
            (state.activeReaderController as? VellumPDFView)?.saveBeforeDismantle = nil
            host.rootView = AnyView(EmptyView())
            window.close()
            preferences.cleanup()
        }
    }

    @MainActor
    private struct CloseCommandFixture {
        let preferences: TestPreferences
        let directory: URL
        let urls: [URL]
        let state: AppState
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init(tabCount: Int, useRealDocument: Bool = false) throws {
            _ = NSApplication.shared
            preferences = try TestPreferences()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.directory = directory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sample: URL
            if useRealDocument {
                sample = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("docs/samples/the-shape-of-attention.pdf")
            } else {
                sample = directory.appendingPathComponent("sample.pdf")
                let data = NSMutableData()
                var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
                let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
                let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
                for _ in 0..<2 {
                    context.beginPDFPage(nil)
                    context.setStrokeColor(NSColor.black.cgColor)
                    context.stroke(CGRect(x: 72, y: 72, width: 468, height: 648))
                    context.endPDFPage()
                }
                context.closePDF()
                try (data as Data).write(to: sample)
            }
            urls = try (0..<tabCount).map { index in
                let url = directory.appendingPathComponent("reader-close-\(index).pdf")
                try FileManager.default.copyItem(at: sample, to: url)
                return url
            }
            state = makeTestAppState(defaults: preferences.defaults)
            host = NSHostingView(rootView: AnyView(ReaderStack(emptyScale: 1).environmentObject(state)))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
        }

        func cleanUp() {
            window.contentView = nil
            window.close()
            preferences.cleanup()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

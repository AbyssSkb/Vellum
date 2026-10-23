import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("File operation feedback")
struct FileFeedbackTests {
    @Test(arguments: [false, true], [false, true])
    func failedOpenExplainsReasonAndPreservesCurrentDocument(missing: Bool, newTabs: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let originalURL = fixture.url("original.pdf")
        try fixture.writePDF(to: originalURL)
        fixture.state.openInCurrentTab(url: originalURL)
        let original = try #require(fixture.state.selectedTab)
        let document = try #require(original.document)
        let persistence = PDFAnnotationPersistence.existing(for: document)
        #expect(fixture.toasts.isEmpty)
        let failedURL = fixture.url(missing ? "missing.pdf" : "invalid.pdf")
        if !missing { try Data("Not a PDF".utf8).write(to: failedURL) }

        if newTabs {
            fixture.state.openInNewTabs(urls: [failedURL])
        } else {
            fixture.state.openInCurrentTab(url: failedURL)
        }

        #expect(fixture.state.tabs.count == 1)
        #expect(fixture.state.selectedTabID == original.id)
        #expect(fixture.state.selectedTab?.document === document)
        #expect(document.documentURL == originalURL)
        #expect(PDFAnnotationPersistence.existing(for: document) === persistence)
        let language = AppUILanguage.saved()
        let reason = language.text(missing ? .fileMissing : .fileUnparseable)
        #expect(fixture.toasts.count == 1)
        #expect(fixture.toasts.first?.message == language.text(.fileOpenFailed(
            name: failedURL.lastPathComponent, reason: reason
        )))
    }

    @Test(arguments: [false, true])
    func batchFailureIsAggregatedWithEveryReason(allFailed: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let readable = fixture.url("readable.pdf")
        try fixture.writePDF(to: readable)
        let invalid = fixture.url("invalid.pdf")
        try Data("Not a PDF".utf8).write(to: invalid)
        let missing = fixture.url("missing.pdf")

        fixture.state.openInNewTabs(urls: (allFailed ? [] : [readable]) + [invalid, missing])

        let opened = allFailed ? 0 : 1
        #expect(fixture.state.tabs.count == opened)
        #expect(fixture.toasts.count == 1)
        let message = try #require(fixture.toasts.first?.message)
        let language = AppUILanguage.saved()
        #expect(message.hasPrefix(language.text(.fileBatchOpenFailed(opened: opened, failed: 2))))
        #expect(message.contains(language.text(.fileOpenFailed(
            name: invalid.lastPathComponent, reason: language.text(.fileUnparseable)
        ))))
        #expect(message.contains(language.text(.fileOpenFailed(
            name: missing.lastPathComponent, reason: language.text(.fileMissing)
        ))))
        #expect(fixture.toasts.first?.toolTip == message)
    }

    @Test
    func readFailureUsesConfirmedReasonRatherThanAssumingInvalidPDF() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let unreadable = fixture.url("unreadable.pdf")
        try fixture.writePDF(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }

        fixture.state.openInCurrentTab(url: unreadable)

        #expect(fixture.state.tabs.isEmpty)
        let language = AppUILanguage.saved()
        #expect(fixture.toasts.first?.message == language.text(.fileOpenFailed(
            name: unreadable.lastPathComponent, reason: language.text(.filePermissionDenied)
        )))
    }

    @Test
    func restoreDistinguishesEmptyHistoryAndFailedFileAndAllowsRetry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let language = AppUILanguage.saved()
        fixture.state.restoreClosedPDFTab()
        #expect(fixture.toasts.first?.message == language.text(.noClosedTabs))
        let url = fixture.url("closed.pdf")
        try fixture.writePDF(to: url)
        fixture.state.openInCurrentTab(url: url)
        let snapshot = ReaderSnapshot(pageIndex: 0, pointOnPage: NSPoint(x: 25, y: 30),
                                      scrollOrigin: nil, scaleFactor: 1.4, autoScales: false)
        fixture.state.saveSnapshot(snapshot, for: try #require(fixture.state.selectedTabID))
        fixture.state.closeSelectedTab()
        try FileManager.default.removeItem(at: url)

        fixture.state.restoreClosedPDFTab()

        #expect(fixture.state.tabs.isEmpty)
        #expect(fixture.state.tabStore.nextClosedPDFTabURL == url)
        #expect(fixture.toasts.first?.message == language.text(.fileRestoreFailed(
            name: url.lastPathComponent, reason: language.text(.fileMissing)
        )))
        try fixture.writePDF(to: url)
        fixture.state.restoreClosedPDFTab()
        #expect(fixture.state.selectedTab?.url == url)
        #expect(fixture.state.selectedTab?.snapshot == snapshot)
        #expect(fixture.state.tabStore.nextClosedPDFTabURL == nil)
    }

    @Test(arguments: [false, true])
    func sessionRestoreAggregatesFailuresOnceAndKeepsUnresolvedEntries(allFailed: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let readable = fixture.url("readable.pdf")
        try fixture.writePDF(to: readable)
        let missing = PersistedPDFTab(path: fixture.url("missing.pdf").path, snapshot: .initial)
        let unreadable = PersistedPDFTab(path: fixture.url("invalid.pdf").path, snapshot: .initial)
        try Data("Not a PDF".utf8).write(to: URL(fileURLWithPath: unreadable.path))
        let session = PersistedAppSession(tabs: (allFailed ? [] : [PersistedPDFTab(path: readable.path, snapshot: .initial)])
                                          + [missing, unreadable], selectedURLPath: missing.path)
        fixture.defaults.set(true, forKey: AppPreferenceKeys.restorePreviousTabs)
        fixture.defaults.set(try JSONEncoder().encode(session), forKey: "VellumPreviousSession")

        fixture.state.restorePreviousTabsIfNeeded()

        #expect(fixture.state.tabs.count == (allFailed ? 0 : 1))
        #expect(fixture.state.unresolvedSession?.tabs == [missing, unreadable])
        let toast = try #require(fixture.toasts.first)
        let language = AppUILanguage.saved()
        #expect(toast.message.hasPrefix(language.text(.fileSessionRestoreFailed(restored: allFailed ? 0 : 1, failed: 2))))
        #expect(toast.message.contains(language.text(.fileMissing)))
        #expect(toast.message.contains(language.text(.fileUnparseable)))
        fixture.state.restorePreviousTabsIfNeeded()
        #expect(fixture.toasts.count == 1)
        #expect(fixture.toasts.first === toast)
        fixture.state.saveCurrentSession()
        #expect(AppSessionPersistence.load(defaults: fixture.defaults)?.tabs == session.tabs)
    }

    @MainActor
    private struct Fixture {
        let directory: URL
        let window: NSWindow
        let state: AppState
        let defaults: UserDefaults
        let suiteName: String

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("vellum-feedback-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            suiteName = "Vellum.FileFeedbackTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            state = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
                installsKeyMonitor: false, installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()))
            state.readerWindow = window
        }

        var toasts: [ToastView] {
            window.contentView?.superview?.subviews.compactMap { $0 as? ToastView } ?? []
        }

        func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

        func writePDF(to url: URL) throws {
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: 0)
            try #require(document.dataRepresentation()).write(to: url, options: .atomic)
        }

        func cleanUp() {
            window.close()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

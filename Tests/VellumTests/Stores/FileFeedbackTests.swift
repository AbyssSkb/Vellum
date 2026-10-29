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
        #expect(message == language.text(.fileBatchOpenFailed(opened: opened, failed: 2)))
        let details = try fixture.failureDetails()
        #expect(details.contains(language.text(.fileOpenFailed(
            name: invalid.lastPathComponent, reason: language.text(.fileUnparseable)
        ))))
        #expect(details.contains(language.text(.fileOpenFailed(
            name: missing.lastPathComponent, reason: language.text(.fileMissing)
        ))))
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
        #expect(toast.message == language.text(.fileSessionRestoreFailed(restored: allFailed ? 0 : 1, failed: 2)))
        let details = try fixture.failureDetails()
        #expect(details.contains(language.text(.fileMissing)))
        #expect(details.contains(language.text(.fileUnparseable)))
        fixture.state.restorePreviousTabsIfNeeded()
        #expect(fixture.toasts.count == 1)
        #expect(fixture.toasts.first === toast)
        fixture.state.saveCurrentSession()
        #expect(AppSessionPersistence.load(defaults: fixture.defaults)?.tabs == session.tabs)
    }

    @Test
    func sessionFailureDetailsWaitForWindowAndSurviveOtherNotifications() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.state.readerWindow = nil
        let missing = PersistedPDFTab(path: fixture.url("missing.pdf").path, snapshot: .initial)
        let another = PersistedPDFTab(path: fixture.url("another.pdf").path, snapshot: .initial)
        let session = PersistedAppSession(tabs: [missing, another], selectedURLPath: missing.path)
        fixture.defaults.set(true, forKey: AppPreferenceKeys.restorePreviousTabs)
        fixture.defaults.set(try JSONEncoder().encode(session), forKey: "VellumPreviousSession")

        fixture.state.restorePreviousTabsIfNeeded()
        fixture.state.showNotification("Another notification", kind: .info)

        #expect(fixture.state.pendingFileFailureDetails.count == 1)
        fixture.state.readerWindow = fixture.window
        try await waitForTestCondition("The pending failure sheet appears") {
            fixture.window.attachedSheet != nil
        }
        let details = try fixture.failureDetails()
        #expect(details.contains("missing.pdf"))
        #expect(details.contains(AppUILanguage.saved().text(.fileMissing)))
    }

    @Test(arguments: [false, true])
    func singleSessionFileFailureUsesOnlyToast(duplicated: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let missing = PersistedPDFTab(path: fixture.url("missing.pdf").path, snapshot: .initial)
        let session = PersistedAppSession(tabs: duplicated ? [missing, missing] : [missing],
                                          selectedURLPath: missing.path)
        fixture.defaults.set(true, forKey: AppPreferenceKeys.restorePreviousTabs)
        fixture.defaults.set(try JSONEncoder().encode(session), forKey: "VellumPreviousSession")

        fixture.state.restorePreviousTabsIfNeeded()

        let language = AppUILanguage.saved()
        #expect(fixture.toasts.first?.message == language.text(.fileRestoreFailed(
            name: "missing.pdf", reason: language.text(.fileMissing)
        )))
        #expect(fixture.window.attachedSheet == nil)
        #expect(fixture.state.pendingFileFailureDetails.isEmpty)
        #expect(fixture.state.unresolvedSession?.tabs == [missing])
    }

    @Test
    func batchFailureDetailsScrollToTheLastFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let urls = (0..<40).map { fixture.url("missing-\($0).pdf") }
        fixture.state.openInNewTabs(urls: urls)

        let text = try fixture.failureDetailsView()
        let layout = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        layout.ensureLayout(for: container)
        text.scrollToEndOfDocument(nil)
        let glyphs = layout.glyphRange(
            forCharacterRange: NSRange(location: text.string.utf16.count - 1, length: 1),
            actualCharacterRange: nil
        )
        let lastGlyph = layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        #expect(text.string.contains("missing-39.pdf"))
        #expect(text.bounds.height > text.visibleRect.height)
        #expect(lastGlyph.maxY <= text.visibleRect.maxY + 1)
        #expect(lastGlyph.minY >= text.visibleRect.minY - 1)
    }

    @Test
    func queuedFailureSheetsRemainAvailableAndRestoreFocus() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let field = NSTextField(string: "reader focus")
        try #require(fixture.window.contentView).addSubview(field)
        #expect(fixture.window.makeFirstResponder(field))
        let originalFocus = fixture.window.firstResponder
        fixture.state.readerWindow = nil
        fixture.state.openInNewTabs(urls: [fixture.url("first-a.pdf"), fixture.url("first-b.pdf")])
        fixture.state.openInNewTabs(urls: [fixture.url("second-a.pdf"), fixture.url("second-b.pdf")])
        #expect(fixture.state.pendingFileFailureDetails.count == 2)

        fixture.state.readerWindow = fixture.window
        fixture.state.showPendingFileFailureDetails()
        let first = try #require(fixture.window.attachedSheet)
        #expect(try fixture.failureDetails().contains("first-a.pdf"))
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                  timestamp: 0, windowNumber: first.windowNumber, context: nil,
                                                  characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                  isARepeat: false, keyCode: 53))
        first.sendEvent(event)
        try await waitForTestCondition("The next failure sheet appears") {
            fixture.window.attachedSheet != nil && fixture.window.attachedSheet !== first
        }
        let second = try #require(fixture.window.attachedSheet)
        #expect(try fixture.failureDetails().contains("second-a.pdf"))
        let escapeEvent = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                        timestamp: 0, windowNumber: second.windowNumber, context: nil,
                                                        characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                        isARepeat: false, keyCode: 53))
        second.sendEvent(escapeEvent)
        try await waitForTestCondition("The failure sheets close") { fixture.window.attachedSheet == nil }
        #expect(fixture.window.firstResponder === originalFocus)
    }

    @Test
    func failureDetailsWaitForAnExistingSheet() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let otherSheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                  styleMask: .titled, backing: .buffered, defer: false)
        fixture.window.beginSheet(otherSheet, completionHandler: nil)
        fixture.state.openInNewTabs(urls: [fixture.url("first.pdf"), fixture.url("second.pdf")])
        #expect(fixture.window.attachedSheet === otherSheet)
        fixture.window.endSheet(otherSheet)
        try await waitForTestCondition("The queued failure details appear") {
            fixture.window.attachedSheet != nil && fixture.window.attachedSheet !== otherSheet
        }
        #expect(try fixture.failureDetails().contains("first.pdf"))
    }

    @Test
    func pendingFailureDetailsFollowAReplacementWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let oldSheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                styleMask: .titled, backing: .buffered, defer: false)
        fixture.window.beginSheet(oldSheet, completionHandler: nil)
        fixture.state.openInNewTabs(urls: [fixture.url("first.pdf"), fixture.url("second.pdf")])
        let replacement = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                   styleMask: .titled, backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        defer {
            if let sheet = replacement.attachedSheet { replacement.endSheet(sheet) }
            replacement.close()
        }
        fixture.state.readerWindow = replacement
        fixture.window.endSheet(oldSheet)
        fixture.window.close()
        try await waitForTestCondition("Pending failure details follow the replacement window") {
            replacement.attachedSheet != nil
        }
    }

    @Test
    func visibleFailureDetailsFollowAReplacementWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.state.openInNewTabs(urls: [fixture.url("first.pdf"), fixture.url("second.pdf")])
        #expect(try fixture.failureDetails().contains("first.pdf"))
        let replacement = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                   styleMask: .titled, backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        defer {
            if let sheet = replacement.attachedSheet { replacement.endSheet(sheet) }
            replacement.close()
        }
        fixture.state.readerWindow = replacement
        try await waitForTestCondition("The open failure details follow the replacement window") {
            replacement.attachedSheet != nil
        }
        #expect(fixture.window.attachedSheet == nil)
        #expect(fixture.state.pendingFileFailureDetails.first?.details.contains("first.pdf") == true)
    }

    @Test
    func closingReaderKeepsVisibleFailureDetailsForTheNextWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.state.openInNewTabs(urls: [fixture.url("first.pdf"), fixture.url("second.pdf")])
        _ = try #require(fixture.window.attachedSheet)
        fixture.window.close()
        try await waitForTestCondition("The closed reader releases its window") {
            fixture.state.readerWindow == nil
        }
        #expect(fixture.state.pendingFileFailureDetails.first?.details.contains("first.pdf") == true)
        let replacement = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                   styleMask: .titled, backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        defer {
            if let sheet = replacement.attachedSheet { replacement.endSheet(sheet) }
            replacement.close()
        }
        fixture.state.readerWindow = replacement
        try await waitForTestCondition("The next reader receives the failure details") {
            replacement.attachedSheet != nil
        }
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

        func failureDetailsView() throws -> NSTextView {
            let sheet = try #require(window.attachedSheet)
            sheet.contentView?.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }
            let views = descendants(try #require(sheet.contentView))
            let text = try #require(views.compactMap { $0 as? NSTextView }.first)
            #expect(text.enclosingScrollView?.hasVerticalScroller == true)
            #expect(!text.isEditable)
            return text
        }

        func failureDetails() throws -> String { try failureDetailsView().string }

        func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

        func writePDF(to url: URL) throws {
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: 0)
            try #require(document.dataRepresentation()).write(to: url, options: .atomic)
        }

        func cleanUp() {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

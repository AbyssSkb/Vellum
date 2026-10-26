import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Dictionary reader interaction")
struct PDFDictionaryInteractionTests {
    @Test
    func doubleClickLookupFitsTheCanvasAndEscapeClearsTheReaderSelection() async throws {
        try await withReader { window, view, page in
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            view.performDoubleClickActionIfNeeded(at: point)
            #expect(view.isDictionaryInteractionActive)
            let overlay = try #require(view.dictionaryOverlay)
            #expect(view.visibleRect.insetBy(dx: 17, dy: 17).contains(overlay.frame))
            let escape = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
            ))
            #expect(view.handleDictionaryKeyEvent(escape))
            #expect(!view.isDictionaryInteractionActive)
            let retainedSelection = view.currentSelection != nil
            #expect(!retainedSelection)
            #expect(view.textSelectionNavigationState == nil)
            #expect(window.firstResponder === view)
        }
    }

    @Test(arguments: [true, false])
    func reopeningTheDictionaryReusesItsWebView(restoreFocus: Bool) async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            let first = try #require(view.dictionaryPopover)
            view.dismissDictionaryPopover(restoreFocus: restoreFocus)
            #expect(!view.isDictionaryInteractionActive)
            view.vimLookupDictionary()
            #expect(view.dictionaryPopover === first)
        }
    }

    @Test
    func changingDictionaryFilesDoesNotReuseThePreviousPage() async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            let first = try #require(view.dictionaryPopover)
            first.dismiss()
            UserDefaults.standard.set("/another-dictionary-test.mdx", forKey: AppPreferenceKeys.dictionaryPath)
            view.vimLookupDictionary()
            #expect(view.dictionaryPopover !== first)
        }
    }

    @Test
    func dictionaryPresentsTheEntryAtItsMeasuredHeightWithoutFlashingALoadingPanel() async throws {
        try await withReader { _, view, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryReveal-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("hello", Data("<div style='height:300px'>Definition</div>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)

            view.vimLookupDictionary()
            let popover = try #require(view.dictionaryPopover)
            let overlay = try #require(view.dictionaryOverlay)
            var viewportHeightWhenRevealed: CGFloat?
            let onLoadingChange = popover.onLoadingChange
            popover.onLoadingChange = { [weak popover] loading in
                onLoadingChange?(loading)
                if !loading { viewportHeightWhenRevealed = popover?.webView.bounds.height }
            }
            #expect(popover.isLoading)
            #expect(!overlay.isHidden)
            #expect(overlay.alphaValue == 0)
            try await waitForTestCondition("The dictionary entry is ready to present", dispatchAppKitEvents: true) { !popover.isLoading }
            #expect(overlay.alphaValue == 1)
            #expect(overlay.frame.height > 300)
            let viewportHeight = try #require(viewportHeightWhenRevealed)
            #expect(abs(viewportHeight - overlay.frame.height + 43) < 1)

            popover.lookup("hello")
            #expect(overlay.alphaValue == 0)
            try await waitForTestCondition("The next dictionary entry is ready to present", dispatchAppKitEvents: true) { !popover.isLoading }
            #expect(overlay.alphaValue == 1)
            #expect(overlay.frame.height > 300)

            popover.lookup("missing")
            try await waitForTestCondition("A missing entry displays its result", dispatchAppKitEvents: true) { !popover.isLoading }
            #expect(overlay.alphaValue == 1)
            #expect(overlay.frame.height == 160)
        }
    }

    @Test
    func dictionaryHeightStartsCompactAndFollowsShortContent() async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            let popover = try #require(view.dictionaryPopover)
            let overlay = try #require(view.dictionaryOverlay)
            #expect(overlay.frame.height <= 180)
            popover.onPreferredHeightChange?(300)
            #expect(abs(overlay.frame.height - 300) < 1)
            popover.onPreferredHeightChange?(180)
            #expect(abs(overlay.frame.height - 180) < 1)
        }
    }

    @Test
    func longDictionaryContentUsesTheAvailableCanvasHeight() async throws {
        try await withReader { window, view, _ in
            window.setContentSize(NSSize(width: 850, height: 1_000))
            window.contentView?.layoutSubtreeIfNeeded()
            view.vimLookupDictionary()
            let popover = try #require(view.dictionaryPopover)
            let overlay = try #require(view.dictionaryOverlay)
            popover.onPreferredHeightChange?(2_000)
            #expect(overlay.frame.height > 620)
            #expect(abs(overlay.frame.height - (view.visibleRect.height - 94)) < 1)
            #expect(overlay.frame.width == 600)
            #expect(view.visibleRect.insetBy(dx: 17, dy: 17).contains(overlay.frame))
        }
    }

    @Test
    func resizingTheCanvasClampsAndRestoresTheDictionaryPreferredHeight() async throws {
        try await withReader { window, view, _ in
            view.vimLookupDictionary()
            let popover = try #require(view.dictionaryPopover)
            let overlay = try #require(view.dictionaryOverlay)
            popover.onPreferredHeightChange?(300)
            window.setContentSize(NSSize(width: 420, height: 280))
            window.contentView?.layoutSubtreeIfNeeded()
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            #expect(abs(overlay.frame.height - (view.visibleRect.height - 94)) < 1)
            #expect(view.visibleRect.insetBy(dx: 17, dy: 17).contains(overlay.frame))
            window.setContentSize(NSSize(width: 520, height: 700))
            window.contentView?.layoutSubtreeIfNeeded()
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            #expect(abs(overlay.frame.height - 300) < 1)
        }
    }

    @Test
    func doubleClickUsesTheConfiguredActionAndIgnoresPointsOutsideTheSelection() async throws {
        try await withReader { _, view, page in
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
            UserDefaults.standard.set(DoubleClickActionPreference.none.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            view.performDoubleClickActionIfNeeded(at: point)
            #expect(!view.isDictionaryInteractionActive)

            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            view.performDoubleClickActionIfNeeded(at: NSPoint(x: -100, y: -100))
            #expect(!view.isDictionaryInteractionActive)
            view.performDoubleClickActionIfNeeded(at: point)
            #expect(view.isDictionaryInteractionActive)
        }
    }

    @Test
    func replacingTheDocumentDismissesTheDictionary() async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            #expect(view.isDictionaryInteractionActive)
            view.document = try makeTextPDF(pages: [[("another", NSPoint(x: 72, y: 720))]])
            #expect(!view.isDictionaryInteractionActive)
        }
    }

    @Test(arguments: [NSWindow.didResignKeyNotification, NSWindow.willMiniaturizeNotification, NSWindow.willCloseNotification])
    func leavingTheReaderCancelsPendingLookupAndPronunciation(notification: Notification.Name) async throws {
        try await withReader { window, view, _ in
            let selectedText = view.currentSelection?.string
            view.vimLookupDictionary()
            #expect(view.isDictionaryInteractionActive)
            NotificationCenter.default.post(name: notification, object: window)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryLifecycleObservers.isEmpty)
            #expect(view.currentSelection?.string == selectedText)
        }
    }

    @Test
    func dictionaryDoubleClickCompletesOnTheNextMainQueueTurn() async throws {
        try await withReader { window, view, page in
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            view.isMouseSelectingText = true
            view.pendingDoubleClickTextSelectionPoint = point
            view.didHandleDoubleClickTextSelectionMouseDown = true
            let event = try #require(NSEvent.mouseEvent(
                with: .leftMouseUp, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 0
            ))
            view.mouseUp(with: event)
            let completed = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume(returning: !view.isMouseSelectingText)
                }
            }
            #expect(completed)
        }
    }

    @Test
    func delayedDoubleClickDoesNotOpenDictionaryForAHiddenReader() async throws {
        try await withReader { window, view, page in
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            view.isMouseSelectingText = true
            view.pendingDoubleClickTextSelectionPoint = point
            view.didHandleDoubleClickTextSelectionMouseDown = true
            let event = try #require(NSEvent.mouseEvent(
                with: .leftMouseUp, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 0
            ))
            view.mouseUp(with: event)

            window.orderOut(nil)
            #expect(!window.isVisible)
            try await waitForTestCondition("The delayed double-click callback completes") {
                !view.isMouseSelectingText
            }
            let openedDictionary = view.isDictionaryInteractionActive
            let retainedPopover = view.dictionaryPopover != nil
            #expect(!openedDictionary)
            #expect(!retainedPopover)
        }
    }

    private func withReader(_ body: @MainActor (NSWindow, VellumPDFView, PDFPage) async throws -> Void) async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled,
                    AppPreferenceKeys.doubleClickAction]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("/nonexistent-vellum-dictionary-test.mdx", forKey: AppPreferenceKeys.dictionaryPath)
        defaults.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        let document = try makeTextPDF(pages: [[("hello world", NSPoint(x: 72, y: 720))]])
        let page = try #require(document.page(at: 0))
        let view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 520, height: 500))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = PDFReaderContainer(reader: view)
        window.makeKeyAndOrderFront(nil)
        defer {
            view.dismissDictionaryPopover(restoreFocus: false)
            view.cancelPendingRestore()
            view.stopScrollAnimation()
            view.stopZoomState()
            view.readingPositionReportWorkItem?.cancel()
            view.readerStateSaveWorkItem?.cancel()
            window.contentView = nil
            window.close()
        }
        view.document = document
        view.layoutDocumentView()
        let text = try #require(page.string as NSString?)
        let selection = try #require(page.selection(for: text.range(of: "hello")))
        view.setCurrentSelection(selection, animate: false)
        try await body(window, view, page)
    }
}

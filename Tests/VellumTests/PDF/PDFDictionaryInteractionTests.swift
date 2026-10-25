import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Dictionary reader interaction")
struct PDFDictionaryInteractionTests {
    @Test
    func lookupFitsTheCanvasAndEscapeRestoresTheReaderSelection() async throws {
        try await withReader { window, view, _ in
            let selectedText = view.currentSelection?.string
            view.vimLookupDictionary()
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
            #expect(view.currentSelection?.string == selectedText)
            #expect(window.firstResponder === view)
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
            view.vimLookupDictionary()
            #expect(view.isDictionaryInteractionActive)
            NotificationCenter.default.post(name: notification, object: window)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryLifecycleObservers.isEmpty)
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
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer {
            view.dismissDictionaryPopover(restoreFocus: false)
            view.document = nil
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

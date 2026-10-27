import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Dictionary reader interaction")
struct PDFDictionaryInteractionTests {
    @Test
    func dictionaryKeyWithoutSelectionLooksUpTheChosenWord() async throws {
        try await withReader { window, view, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryWordJump-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("world", Data("<p id='definition'>Chosen word definition</p>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
            view.clearTextSelectionForVimNavigation()
            let keyboard = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
            let delegate = DictionaryKeyboardDelegate(reader: view)
            keyboard.delegate = delegate
            defer { keyboard.cancelInput() }

            let start = try keyEvent("K", in: window)
            #expect(keyboard.routeKeyEvent(start))
            #expect(try keyboard.routeKeyEvent(keyEvent("K", in: window, type: .keyUp)))
            #expect(view.isWordJumpActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryAccessTask == nil)
            #expect(try keyboard.routeKeyEvent(keyEvent("w", in: window)))
            #expect(try keyboard.routeKeyEvent(keyEvent("\r", in: window)))

            #expect(!view.isWordJumpActive)
            #expect(view.currentSelection?.string == "world")
            try await waitForDictionary(in: view)
            let popover = try #require(view.dictionaryPopover)
            #expect(window.firstResponder === view.dictionaryOverlay)
            #expect(try !view.handleWordJumpKey(keyEvent("\r", in: window)))
            #expect(view.dictionaryPopover === popover)
            try await waitForTestCondition("The chosen word loads its local definition", dispatchAppKitEvents: true) { !popover.isLoading }
            #expect(try await popover.webView.evaluateJavaScript("document.getElementById('definition')?.textContent") as? String == "Chosen word definition")
        }
    }

    @Test(arguments: [false, true])
    func unconfiguredDictionaryKeyShowsAToastWithoutStartingASelectionOrPopover(hasSelection: Bool) async throws {
        try await withReader { window, view, _ in
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.dictionaryPath)
            if !hasSelection { view.clearTextSelectionForVimNavigation() }
            let keyboard = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
            let delegate = DictionaryKeyboardDelegate(reader: view)
            keyboard.delegate = delegate
            defer { keyboard.cancelInput() }

            let start = try keyEvent("K", in: window)
            #expect(keyboard.routeKeyEvent(start))
            #expect(try keyboard.routeKeyEvent(keyEvent("K", in: window, type: .keyUp)))

            #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.dictionaryUnavailable))
            #expect(!view.isWordJumpActive)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryAccessTask == nil)
            #expect(view.currentSelection == nil)
            #expect(window.firstResponder === view)
        }
    }

    @Test(arguments: ["wordSelection", "access", "popover"])
    func removingTheDictionaryCancelsExistingLookupInteraction(interaction: String) async throws {
        try await withReader { window, view, _ in
            if interaction == "wordSelection" { view.clearTextSelectionForVimNavigation() }
            view.vimLookupDictionary()
            if interaction == "popover" { try await waitForDictionary(in: view) }
            let pendingAccess = view.dictionaryAccessTask
            #expect(interaction != "wordSelection" || view.isWordJumpActive)
            #expect(interaction != "access" || pendingAccess != nil)
            #expect(interaction != "popover" || view.dictionaryPopover != nil)

            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.dictionaryPath)
            view.vimLookupDictionary()
            await pendingAccess?.value
            await nextTestMainQueueTurn()

            #expect(currentToast(in: window)?.message == AppUILanguage.saved().text(.dictionaryUnavailable))
            #expect(!view.isWordJumpActive)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryAccessTask == nil)
            #expect(view.dictionaryAccessCompletion == nil)
            #expect(view.dictionaryLifecycleObservers.isEmpty)
            #expect(view.currentSelection == nil)
            #expect(window.firstResponder === view)
        }
    }

    @Test(arguments: [false, true])
    func missingDictionaryEntryShowsAToastAndReturnsToReading(selectWithDictionaryKey: Bool) async throws {
        try await withReader { window, view, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryMiss-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("another", Data("<p>Another definition</p>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
            if selectWithDictionaryKey { view.clearTextSelectionForVimNavigation() }
            let keyboard = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
            let delegate = DictionaryKeyboardDelegate(reader: view)
            keyboard.delegate = delegate
            defer { keyboard.cancelInput() }

            #expect(try keyboard.routeKeyEvent(keyEvent("K", in: window)))
            #expect(try keyboard.routeKeyEvent(keyEvent("K", in: window, type: .keyUp)))
            if selectWithDictionaryKey {
                #expect(view.isWordJumpActive)
                #expect(try keyboard.routeKeyEvent(keyEvent("h", in: window)))
                #expect(try keyboard.routeKeyEvent(keyEvent("\r", in: window)))
            }
            try await waitForTestCondition("An absent entry reports its result without an empty popover", dispatchAppKitEvents: true) {
                currentToast(in: window)?.message == AppUILanguage.saved().text(.dictionaryNotFound("hello"))
            }

            #expect(!view.isWordJumpActive)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryOverlay == nil)
            #expect(view.dictionaryAccessTask == nil)
            #expect(view.dictionaryLifecycleObservers.isEmpty)
            #expect(view.dictionaryDismissMonitor == nil)
            #expect(view.currentSelection == nil)
            #expect(window.firstResponder === view)
            #expect(try keyboard.routeKeyEvent(keyEvent("j", in: window)))
            #expect(!view.isDictionaryInteractionActive)
        }
    }

    @Test
    func anUnreadableDictionaryKeepsItsErrorDistinctFromAMissingEntry() async throws {
        try await withReader { window, view, _ in
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
            let popover = try #require(view.dictionaryPopover)
            try await waitForTestCondition("The unreadable dictionary reports its error", dispatchAppKitEvents: true) { !popover.isLoading }

            #expect(view.isDictionaryInteractionActive)
            #expect(currentToast(in: window) == nil)
            #expect(view.currentSelection?.string == "hello")
        }
    }

    @Test(arguments: ["application", "window", "document", "close"])
    func cancellingAMissingEntryLookupDoesNotShowALateToast(cancellation: String) async throws {
        try await withReader { window, view, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryCancelledMiss-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("hello", Data("<p>Definition</p>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
            let popover = try #require(view.dictionaryPopover)
            try await waitForTestCondition("The entry loads before testing cancellation", dispatchAppKitEvents: true) { !popover.isLoading }
            let selectedText = view.currentSelection?.string

            popover.lookup("missing")
            #expect(popover.isLoading)
            switch cancellation {
            case "application":
                NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
            case "window":
                NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            case "document":
                view.document = try makeTextPDF(pages: [[("another", NSPoint(x: 72, y: 720))]])
            default:
                window.close()
            }
            await nextTestMainQueueTurn()
            await DictionaryStore.shared.invalidate()
            await nextTestMainQueueTurn()

            #expect(currentToast(in: window) == nil)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryLifecycleObservers.isEmpty)
            if cancellation != "document" { #expect(view.currentSelection?.string == selectedText) }
        }
    }

    @Test(arguments: ["escape", "application", "window"])
    func cancellingDictionaryWordJumpDoesNotTurnOrdinarySelectionIntoALookup(cancellation: String) async throws {
        try await withReader { window, view, _ in
            view.clearTextSelectionForVimNavigation()
            let keyboard = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
            let delegate = DictionaryKeyboardDelegate(reader: view)
            keyboard.delegate = delegate
            defer { keyboard.cancelInput() }
            let start = try keyEvent("K", in: window)
            #expect(keyboard.routeKeyEvent(start))
            #expect(try keyboard.routeKeyEvent(keyEvent("K", in: window, type: .keyUp)))
            #expect(view.isWordJumpActive)
            switch cancellation {
            case "application":
                NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
            case "window":
                NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            default:
                #expect(try keyboard.routeKeyEvent(keyEvent("\u{1b}", in: window)))
            }
            #expect(!view.isWordJumpActive)
            #expect(view.dictionaryAccessTask == nil)
            #expect(try keyboard.routeKeyEvent(keyEvent("s", in: window)))
            #expect(try keyboard.routeKeyEvent(keyEvent("s", in: window, type: .keyUp)))
            #expect(try keyboard.routeKeyEvent(keyEvent("w", in: window)))
            #expect(try keyboard.routeKeyEvent(keyEvent("\r", in: window)))
            #expect(view.currentSelection?.string == "world")
            #expect(!view.isWordJumpActive)
            #expect(view.dictionaryAccessTask == nil)
            #expect(view.dictionaryPopover == nil)
        }
    }

    @Test
    func doubleClickLookupFitsTheCanvasAndEscapeClearsTheReaderSelection() async throws {
        try await withReader { window, view, page in
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            view.performDoubleClickActionIfNeeded(at: point)
            try await waitForDictionary(in: view)
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
            try await waitForDictionary(in: view)
            let first = try #require(view.dictionaryPopover)
            view.dismissDictionaryPopover(restoreFocus: restoreFocus)
            #expect(!view.isDictionaryInteractionActive)
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
            #expect(view.dictionaryPopover === first)
        }
    }

    @Test
    func changingDictionaryFilesDoesNotReuseThePreviousPage() async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
            let first = try #require(view.dictionaryPopover)
            first.dismiss()
            UserDefaults.standard.set("/another-dictionary-test.mdx", forKey: AppPreferenceKeys.dictionaryPath)
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
            #expect(view.dictionaryPopover !== first)
        }
    }

    @Test
    func dictionaryPresentsTheEntryAtItsMeasuredHeightWithoutFlashingALoadingPanel() async throws {
        try await withReader { window, view, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryReveal-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("hello", Data("<div style='height:300px'>Definition <a id='missing' href='entry://missing'>Missing entry</a></div>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)

            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
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

            _ = try await popover.webView.evaluateJavaScript("document.getElementById('missing').click()")
            try await waitForTestCondition("A missing entry closes the popover and shows a toast", dispatchAppKitEvents: true) {
                currentToast(in: window)?.message == AppUILanguage.saved().text(.dictionaryNotFound("missing"))
            }
            #expect(!view.isDictionaryInteractionActive)
            #expect(overlay.superview == nil)
            #expect(view.currentSelection == nil)
            #expect(window.firstResponder === view)
        }
    }

    @Test
    func firstDoubleClickContinuesAfterDictionaryPermissionInterruptsFocus() async throws {
        try await withReader { window, view, page in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryPermission-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("hello", Data("<p id='definition'>First lookup definition</p>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)

            view.performDoubleClickActionIfNeeded(at: point)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)

            try await waitForTestCondition("The first lookup presents after permission returns focus", dispatchAppKitEvents: true) {
                view.dictionaryPopover?.isLoading == false && view.dictionaryOverlay?.alphaValue == 1
            }
            let popover = try #require(view.dictionaryPopover)
            #expect(view.isDictionaryInteractionActive)
            #expect(try await popover.webView.evaluateJavaScript("document.getElementById('definition')?.textContent") as? String == "First lookup definition")
        }
    }

    @Test(arguments: [true, false])
    func firstDoubleClickWaitsForTheReaderToRegainKeyAfterPermission(applicationActivationFirst: Bool) async throws {
        try await withReader { window, view, page in
            let window = try #require(window as? DictionaryReaderTestWindow)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDictionaryPermissionFocus-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mdx = directory.appendingPathComponent("fixture.mdx")
            try MDictFixture(entries: [("hello", Data("<p id='definition'>Permission restored definition</p>".utf8))]).data.write(to: mdx)
            UserDefaults.standard.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
            UserDefaults.standard.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
            let bounds = try #require(view.currentSelection?.bounds(for: page))
            let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)

            view.performDoubleClickActionIfNeeded(at: point)
            window.reportedKeyWindow = false
            let pending = try #require(view.dictionaryAccessTask)
            await pending.value
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)

            if applicationActivationFirst {
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
                #expect(view.dictionaryPopover == nil)
            }
            window.reportedKeyWindow = true
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            if !applicationActivationFirst {
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            }
            try await waitForTestCondition("The first lookup resumes when the permission prompt returns key focus", dispatchAppKitEvents: true) {
                view.dictionaryPopover?.isLoading == false && view.dictionaryOverlay?.alphaValue == 1
            }
            let popover = try #require(view.dictionaryPopover)
            #expect(try await popover.webView.evaluateJavaScript("document.getElementById('definition')?.textContent") as? String == "Permission restored definition")
        }
    }

    @Test
    func dictionaryHeightStartsCompactAndFollowsShortContent() async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
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
            try await waitForDictionary(in: view)
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
            try await waitForDictionary(in: view)
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
            try await waitForDictionary(in: view)
            #expect(view.isDictionaryInteractionActive)
        }
    }

    @Test
    func replacingTheDocumentDismissesTheDictionary() async throws {
        try await withReader { _, view, _ in
            view.vimLookupDictionary()
            try await waitForDictionary(in: view)
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
            try await waitForDictionary(in: view)
            #expect(view.isDictionaryInteractionActive)
            NotificationCenter.default.post(name: notification, object: window)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(view.dictionaryLifecycleObservers.isEmpty)
            #expect(view.currentSelection?.string == selectedText)
        }
    }

    @Test(arguments: ["escape", "dismiss", "document", "selection", "dictionary", "hide", "minimize", "close", "anotherWindow"], [false, true])
    func cancelledDictionaryAccessDoesNotPresentALateLookup(action: String, afterAccess: Bool) async throws {
        try await withReader { window, view, page in
            let readerWindow = try #require(window as? DictionaryReaderTestWindow)
            view.vimLookupDictionary()
            let pending = try #require(view.dictionaryAccessTask)
            if afterAccess {
                readerWindow.reportedKeyWindow = false
                await pending.value
                #expect(view.dictionaryAccessCompletion != nil)
            }
            var otherWindow: NSWindow?
            defer { otherWindow?.close() }
            switch action {
            case "escape":
                #expect(view.handleTextSelectionKey("\u{1b}", eventType: .keyDown))
            case "dismiss":
                view.dismissDictionaryPopover()
            case "document":
                view.document = try makeTextPDF(pages: [[("another", NSPoint(x: 72, y: 720))]])
            case "selection":
                let text = try #require(page.string as NSString?)
                view.setCurrentSelection(page.selection(for: text.range(of: "world")), animate: false)
            case "dictionary":
                UserDefaults.standard.set("/another-dictionary-test.mdx", forKey: AppPreferenceKeys.dictionaryPath)
            case "hide":
                window.orderOut(nil)
            case "minimize":
                NotificationCenter.default.post(name: NSWindow.willMiniaturizeNotification, object: window)
            case "close":
                NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            case "anotherWindow":
                let other = DictionaryReaderTestWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
                other.isReleasedWhenClosed = false
                otherWindow = other
                other.makeKeyAndOrderFront(nil)
                #expect(other.isKeyWindow)
            default:
                Issue.record("Unexpected cancellation action: \(action)")
            }
            await pending.value
            readerWindow.reportedKeyWindow = true
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            await nextTestMainQueueTurn()
            #expect(view.dictionaryAccessTask == nil)
            #expect(view.dictionaryAccessCompletion == nil)
            #expect(!view.isDictionaryInteractionActive)
            #expect(view.dictionaryPopover == nil)
            #expect(currentToast(in: window) == nil)
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
        if !Self.didFinishLaunching {
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            Self.didFinishLaunching = true
        }
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
        let window = DictionaryReaderTestWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = PDFReaderContainer(reader: view)
        NSApp.activate(ignoringOtherApps: true)
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
        try await waitForTestCondition("The dictionary reader is active", dispatchAppKitEvents: true) {
            NSApp.isActive && window.isKeyWindow
        }
        try await body(window, view, page)
    }

    private static var didFinishLaunching = false

    private func keyEvent(_ key: String, in window: NSWindow, type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: key == "K" ? .shift : [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0))
    }

    private func waitForDictionary(in view: VellumPDFView) async throws {
        try await waitForTestCondition("The dictionary popover is created", dispatchAppKitEvents: true) {
            view.dictionaryPopover != nil
        }
    }

    private func currentToast(in window: NSWindow) -> ToastView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
    }
}

@MainActor
private final class DictionaryKeyboardDelegate: KeyboardControllerDelegate {
    let reader: VellumPDFView
    var activeReaderController: ReaderController? { reader }
    var readerWindow: NSWindow? { reader.window }

    init(reader: VellumPDFView) { self.reader = reader }

    func handleVimCommand(_ command: VimCommand) {
        if command == .lookupDictionary { reader.vimLookupDictionary() }
        if command == .beginWordJump { reader.beginWordJumpCommand() }
    }

    func open(urls: [URL]) {}
}

private final class DictionaryReaderTestWindow: NSWindow {
    var reportedKeyWindow: Bool?
    override var isKeyWindow: Bool { reportedKeyWindow ?? super.isKeyWindow }
    override var canBecomeKey: Bool { true }
}

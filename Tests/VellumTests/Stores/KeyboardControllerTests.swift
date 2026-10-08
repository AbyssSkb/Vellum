@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Keyboard controller")
struct KeyboardControllerTests {
    private let notificationCenter = NotificationCenter()

    @Test
    func shortTabPressSwitchesReadingFocusOnRelease() {
        let controller = KeyboardController(
            tabPageOverviewDelay: 10,
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        #expect(delegate.focusSwitches == 0)
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))

        #expect(delegate.commands.isEmpty)
        #expect(delegate.focusSwitches == 1)
        #expect(delegate.reader.actions == [])
    }

    @Test
    func longTabPressBeginsMovesAndFinishesPageOverview() throws {
        let controller = KeyboardController(
            tabPageOverviewDelay: 0.001,
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        try waitForPageOverview(delegate.reader)

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "l", keyCode: 37)))
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "l", keyCode: 37)))
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))

        #expect(delegate.commands == [])
        #expect(delegate.readerFocusRequests == 1)
        #expect(delegate.reader.actions == [
            .beginPageOverview,
            .movePageOverview(.next),
            .finishPageOverview
        ])
    }

    @Test(arguments: [false, true])
    func outlineTabUsesTheSameTapAndHoldGesture(holdsTab: Bool) throws {
        let window = makeWindow()
        defer { window.close() }
        let outline = PDFOutlineKeyView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(outline)
        #expect(window.makeFirstResponder(outline))
        let controller = KeyboardController(
            tabPageOverviewDelay: holdsTab ? 0.001 : 10,
            installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.readerWindow = window
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "\t"
        event.physicalKeyCode = 48
        #expect(controller.routeKeyEvent(event))
        #expect(window.firstResponder === outline)
        #expect(delegate.focusSwitches == 0)
        if holdsTab {
            try waitForPageOverview(delegate.reader)
            event.key = "l"
            #expect(controller.routeKeyEvent(event))
            #expect(window.firstResponder === outline)
            #expect(delegate.reader.actions == [.beginPageOverview, .movePageOverview(.next)])
        }
        event.key = "\t"
        event.eventType = .keyUp
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        #expect(delegate.focusSwitches == (holdsTab ? 0 : 1))
        #expect(delegate.readerFocusRequests == (holdsTab ? 1 : 0))
        #expect(delegate.reader.actions == (holdsTab
            ? [.beginPageOverview, .movePageOverview(.next), .finishPageOverview] : []))
    }

    @Test(arguments: [false, true], ["l", "j"])
    func fastTabNavigationPreviewsBeforeTheHoldThreshold(startsInOutline: Bool, key: String) {
        let window = makeWindow()
        defer { window.close() }
        let responder: NSView = startsInOutline
            ? PDFOutlineKeyView(frame: window.contentView!.bounds)
            : KeyboardFocusView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(responder)
        #expect(window.makeFirstResponder(responder))
        let controller = KeyboardController(
            tabPageOverviewDelay: 10,
            installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.readerWindow = window
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "\t"
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.reader.actions.isEmpty)
        #expect(window.firstResponder === responder)
        event.key = key
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.reader.actions == [.beginPageOverview, .movePageOverview(key == "l" ? .next : .nextRow)])
        #expect(delegate.commands.isEmpty)
        #expect(window.firstResponder === responder)
        event.eventType = .keyUp
        #expect(controller.routeKeyEvent(event))
        event.key = "\t"
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.reader.actions == [
            .beginPageOverview, .movePageOverview(key == "l" ? .next : .nextRow), .finishPageOverview
        ])
        #expect(delegate.focusSwitches == 0)
        #expect(delegate.readerFocusRequests == 1)
        #expect(delegate.commands.isEmpty)
    }

    @Test(arguments: [false, true])
    func armedTabConsumesUnrelatedKeysWithoutMovingEitherPane(startsInOutline: Bool) {
        let window = makeWindow()
        defer { window.close() }
        let responder: NSView = startsInOutline
            ? PDFOutlineKeyView(frame: window.contentView!.bounds)
            : KeyboardFocusView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(responder)
        #expect(window.makeFirstResponder(responder))
        let controller = KeyboardController(
            tabPageOverviewDelay: 10,
            installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.readerWindow = window
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "\t"
        #expect(controller.routeKeyEvent(event))
        for key in ["/", "t", "g", "3"] {
            event.key = key
            event.eventType = .keyDown
            #expect(controller.routeKeyEvent(event))
            event.eventType = .keyUp
            #expect(controller.routeKeyEvent(event))
        }
        #expect(delegate.reader.actions.isEmpty)
        #expect(delegate.commands.isEmpty)
        #expect(window.firstResponder === responder)
        event.key = "\t"
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.focusSwitches == 1)
        #expect(delegate.readerFocusRequests == 0)
    }

    @Test(arguments: [false, true])
    func escapeCancelsTabGestureAndConsumesItsRelease(active: Bool) throws {
        let window = makeWindow()
        defer { window.close() }
        let outline = PDFOutlineKeyView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(outline)
        #expect(window.makeFirstResponder(outline))
        let controller = KeyboardController(
            tabPageOverviewDelay: active ? 0.001 : 10,
            installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.readerWindow = window
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "\t"
        #expect(controller.routeKeyEvent(event))
        if active { try waitForPageOverview(delegate.reader) }
        event.key = "\u{1b}"
        #expect(controller.routeKeyEvent(event))
        #expect(window.firstResponder === outline)
        // An intervening outline movement must not turn the release into a tap.
        event.key = "j"
        #expect(!controller.routeKeyEvent(event))
        event.key = "\t"
        event.eventType = .keyUp
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        #expect(delegate.focusSwitches == 0)
        #expect(delegate.readerFocusRequests == 0)
        #expect(delegate.reader.actions == (active ? [.beginPageOverview, .cancelPageOverview] : []))
        event.eventType = .keyDown
        #expect(controller.routeKeyEvent(event))
        event.eventType = .keyUp
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.focusSwitches == 1)
    }

    @Test
    func galleryEntryResponderChangeRetainsGestureOwnershipAndEscapeRestoresOutline() throws {
        let window = makeWindow()
        defer { window.close() }
        let outline = PDFOutlineKeyView(frame: window.contentView!.bounds)
        let readerView = KeyboardFocusView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(outline)
        window.contentView?.addSubview(readerView)
        #expect(window.makeFirstResponder(outline))
        let controller = KeyboardController(
            tabPageOverviewDelay: 0.001,
            installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.readerWindow = window
        delegate.reader.onBeginPageOverview = { _ = window.makeFirstResponder(readerView) }
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "\t"
        #expect(controller.routeKeyEvent(event))
        try waitForPageOverview(delegate.reader)
        #expect(window.firstResponder === readerView)
        event.key = "l"
        #expect(controller.routeKeyEvent(event))
        event.key = "\u{1b}"
        #expect(controller.routeKeyEvent(event))
        #expect(window.firstResponder === outline)
        event.key = "\t"
        event.eventType = .keyUp
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.reader.actions == [.beginPageOverview, .movePageOverview(.next), .cancelPageOverview])
        #expect(delegate.focusSwitches == 0)
    }

    @Test
    func tabPreservesTextInputSettingsAndShiftTab() {
        let window = makeWindow()
        let settingsWindow = makeWindow()
        defer { window.close(); settingsWindow.close() }
        let editor = NSTextView()
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        delegate.readerWindow = window
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.key = "\t"
        event.physicalKeyCode = 48
        for type: NSEvent.EventType in [.keyDown, .keyUp] {
            event.eventType = type
            event.targetWindow = window
            #expect(!controller.routeKeyEvent(event))
            event.targetWindow = settingsWindow
            #expect(!controller.routeKeyEvent(event))
        }
        #expect(window.makeFirstResponder(nil))
        event.targetWindow = window
        event.eventType = .keyDown
        event.flags = [.shift]
        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        #expect(delegate.focusSwitches == 0)
        #expect(delegate.reader.actions.isEmpty)
    }

    @Test(arguments: ["g", "2"])
    func escapeClearsReaderPrefixesBeforeTextActions(prefix: String) {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: prefix, keyCode: 0)))
        delegate.reader.textSelectionKeyResult = true
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\u{1b}", keyCode: 53)))
        delegate.reader.textSelectionKeyResult = false
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "G", keyCode: 5)))
        #expect(delegate.commands == [.lastPage])
    }

    @Test
    func slashRoutesToSearchCommand() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "/", keyCode: 44)))

        #expect(delegate.commands == [.beginSearch])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func repeatedNSearchKeyRoutesEveryEvent() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "n", keyCode: 45)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "n", keyCode: 45, isRepeat: true)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "N", keyCode: 45, isRepeat: true)))

        #expect(delegate.commands == [.searchNext, .searchNext, .searchPrevious])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func dScrollsWhenOnlySearchTargetExists() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.hasSearchTextTarget = true
        delegate.reader.deleteHighlightsResult = true
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "d", keyCode: 2)))

        #expect(delegate.commands == [.largeScrollDown])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func dDeletesHighlightOnceWhileHeldWhenTextSelectionExists() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.hasNavigableTextSelection = true
        delegate.reader.deleteHighlightsResult = true
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "d", keyCode: 2)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "d", keyCode: 2, isRepeat: true)))
        #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "d", keyCode: 2)))

        #expect(delegate.commands == [])
        #expect(delegate.reader.actions == [.deleteHighlights])
    }

    @Test
    func uppercaseDScrollsEvenWhenTextSelectionExists() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.hasNavigableTextSelection = true
        delegate.reader.deleteHighlightsResult = true
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "D", keyCode: 2)))

        #expect(delegate.commands == [.extraLargeScrollDown])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func uppercaseTRoutesToTabSwitcherCommand() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "T", keyCode: 17)))

        #expect(delegate.commands == [.showTabSwitcher])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func commandShortcutsPassThroughToAppMenus() {
        let controller = KeyboardController(
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: "q", keyCode: 12, modifierFlags: [.command])))

        #expect(delegate.commands == [])
        #expect(delegate.reader.actions == [])
    }

    @Test
    func modifiedKeyReleaseStopsContinuousScrolling() {
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
            let delegate = RecordingKeyboardDelegate()
            controller.delegate = delegate

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
            #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38, modifierFlags: modifier)))
            RunLoop.main.run(until: Date().addingTimeInterval(0.10))
            #expect(delegate.commands == [.scrollDown])

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
            #expect(delegate.commands == [.scrollDown, .scrollDown])
            #expect(controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38)))
        }
    }

    @Test
    func modifierShortcutStopsContinuousScrollingWithoutBeingConsumed() {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: "o", keyCode: 31, modifierFlags: [.command])))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == [.scrollDown])
    }

    @Test
    func deactivationClearsScrollingAndPendingTabPress() {
        for name in [NSApplication.willResignActiveNotification, NSWindow.didResignKeyNotification] {
            let controller = KeyboardController(
                tabPageOverviewDelay: 0.001,
                installsKeyMonitor: false,
                installsOpenURLObserver: false,
                notificationCenter: notificationCenter
            )
            let delegate = RecordingKeyboardDelegate()
            controller.delegate = delegate

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
            notificationCenter.post(name: name, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.10))
            #expect(delegate.commands == [.scrollDown])

            #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
            notificationCenter.post(name: name, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))
            #expect(delegate.commands == [.scrollDown])
            #expect(delegate.reader.actions.isEmpty)
        }
    }

    @Test
    func deactivationDismissesActivePageOverview() throws {
        let controller = KeyboardController(
            tabPageOverviewDelay: 0.001,
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        try waitForPageOverview(delegate.reader)
        notificationCenter.post(name: NSApplication.willResignActiveNotification, object: nil)
        #expect(delegate.reader.actions == [.beginPageOverview, .cancelPageOverview])
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))
    }

    @Test
    func changingFirstResponderStopsContinuousScrolling() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: false)
        let first = NSTextView()
        let second = NSTextView()
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(second)
        #expect(window.makeFirstResponder(first))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate

        let event = WindowKeyboardEvent()
        event.targetWindow = window
        #expect(controller.handleKeyEvent(event))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        let commandsBeforeFocusChange = delegate.commands
        #expect(window.makeFirstResponder(second))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == commandsBeforeFocusChange)
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38)))
    }

    @Test(arguments: ["g", "1"], [false, true])
    func pendingInputBelongsToItsStartingResponderAndReader(firstKey: String, changesReader: Bool) {
        let window = makeWindow()
        defer { window.close() }
        let first = NSTextView()
        let second = NSTextView()
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(second)
        #expect(window.makeFirstResponder(first))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = firstKey
        #expect(controller.handleKeyEvent(event))

        if changesReader {
            delegate.reader = RecordingKeyboardReaderController()
        } else {
            #expect(window.makeFirstResponder(second))
        }
        event.key = firstKey == "g" ? "g" : "2"
        #expect(controller.handleKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        event.key = firstKey == "g" ? "g" : "G"
        #expect(controller.handleKeyEvent(event))
        #expect(delegate.commands == (firstKey == "g" ? [.firstPage] : [.jumpToPage(2)]))
    }

    @Test
    func numericSequenceRetainsItsStartingContextUntilConsumed() {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "1", keyCode: 18)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "2", keyCode: 19)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "G", keyCode: 5)))
        #expect(delegate.commands == [.jumpToPage(12)])
    }

    @Test(arguments: ["g", "1", "/", "T", "H", "L"])
    func startingAnotherCommandStopsHeldScrolling(key: String) {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: key, keyCode: 0)))
        let commands = delegate.commands
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == commands)
        #expect(commands.filter { $0 == .scrollDown }.count == 1)
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38)))
    }

    @Test
    func changingReaderStopsHeldScrollingBeforeItsNextTick() {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "j", keyCode: 38)))
        delegate.reader = RecordingKeyboardReaderController()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == [.scrollDown])
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "j", keyCode: 38)))
    }

    @Test(arguments: ["j", "g"])
    func blockingPresentationCancelsInputBeforeItsEditorTakesFocus(key: String) {
        let window = makeWindow()
        defer { window.close() }
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = key
        #expect(controller.routeKeyEvent(event))
        let commands = delegate.commands
        let readerActions = delegate.reader.actions
        delegate.hasBlockingReaderPresentation = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(!controller.routeKeyEvent(event))
        event.key = "j"
        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.commands == commands)
        #expect(delegate.reader.actions == readerActions)

        delegate.hasBlockingReaderPresentation = false
        event.key = "g"
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands == commands)
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands == commands + [.firstPage])
    }

    @Test
    func hidingInputWindowStopsHeldScrolling() {
        let window = makeWindow()
        defer { window.close() }
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        #expect(controller.routeKeyEvent(event))
        window.orderOut(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        #expect(delegate.commands == [.scrollDown])
        #expect(!controller.routeKeyEvent(event))
        window.orderFront(nil)
        event.eventType = .keyUp
        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.commands == [.scrollDown])
    }

    @Test
    func attachedSheetCancelsReaderPrefixesAndBlocksCommands() throws {
        let window = makeWindow()
        let sheet = makeWindow()
        sheet.orderOut(nil)
        defer {
            window.endSheet(sheet)
            sheet.orderOut(nil)
            sheet.close()
            window.close()
        }
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "g"
        #expect(controller.routeKeyEvent(event))
        window.beginSheet(sheet)
        #expect(window.attachedSheet === sheet)
        #expect(!controller.routeKeyEvent(event))
        event.key = "j"
        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        window.endSheet(sheet)
        sheet.orderOut(nil)
        let deadline = Date().addingTimeInterval(1)
        while window.attachedSheet != nil, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: deadline)
        }
        try #require(window.attachedSheet == nil)
        event.key = "g"
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands == [.firstPage])
    }

    @Test(arguments: [("H", VimCommand.previousTab), ("L", .nextTab)])
    func uppercaseTabCommandsTakePrecedenceOverTextSelection(key: String, command: VimCommand) {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        delegate.reader.textSelectionKeyResult = true
        controller.delegate = delegate
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: key, keyCode: 0, modifierFlags: [.shift])))
        #expect(delegate.commands == [command])
        #expect(delegate.reader.actions.isEmpty)
    }

    @Test(arguments: [
        ("o", UInt16(31), VimCommand.jumpBack),
        ("i", 34, .jumpForward),
        ("O", 34, .jumpBack),
        ("\u{000F}", 0, .jumpBack),
        ("\t", 34, .jumpForward),
        ("\t", 31, .jumpForward),
        ("", 31, .jumpBack)
    ])
    func controlHistoryKeysWorkFromOutline(key: String, keyCode: UInt16, command: VimCommand) {
        let window = makeWindow()
        defer { window.close() }
        let outline = PDFOutlineKeyView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(outline)
        #expect(window.makeFirstResponder(outline))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = key
        event.physicalKeyCode = keyCode
        event.flags = [.control]

        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands == [command])
        #expect(window.firstResponder === outline)
        event.eventType = .keyUp
        #expect(!controller.routeOutlineGlobalKeyEvent(event))
        #expect(delegate.commands == [command])
    }

    @Test(arguments: [false, true])
    func controlTabPreservesItsNativeShortcut(shifted: Bool) {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        let flags: NSEvent.ModifierFlags = shifted ? [.control, .shift] : [.control]

        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48, modifierFlags: flags)))
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48, modifierFlags: flags)))
        #expect(delegate.commands.isEmpty)
        #expect(delegate.focusSwitches == 0)
        #expect(delegate.reader.actions.isEmpty)
    }

    @Test(arguments: ["p", "щ", "ы", "\u{0010}", "\u{0003}"])
    func controlHistoryDoesNotOverrideOtherLayoutCharacters(key: String) {
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: key, keyCode: 31, modifierFlags: [.control])))
        #expect(!controller.handleKeyEvent(keyEvent(.keyDown, key: key, keyCode: 34, modifierFlags: [.control])))
        #expect(delegate.commands.isEmpty)
    }

    @Test
    func controlHistoryPreservesTextEditorAndWindowOwnership() {
        let window = makeWindow()
        let settingsWindow = makeWindow()
        defer { window.close(); settingsWindow.close() }
        let editor = NSTextView()
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "o"
        event.flags = [.control]
        event.physicalKeyCode = 31
        #expect(!controller.routeKeyEvent(event))
        #expect(window.makeFirstResponder(nil))
        event.targetWindow = settingsWindow
        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
    }

    @Test(arguments: [
        ("H", VimCommand.previousTab), ("L", .nextTab), ("o", .open), ("O", .openInNewTab),
        ("x", .closeTab), ("X", .restoreClosedTab), ("T", .showTabSwitcher), ("/", .beginSearch),
        ("A", .showAIExplanationHistory), ("I", .showAIConversationHistory),
        ("[", .previousTab), ("]", .nextTab), ("n", .searchNext), ("N", .searchPrevious)
    ])
    func outlineGlobalCommandsWaitForLocalOutlineHandling(key: String, command: VimCommand) {
        let window = makeWindow()
        defer { window.close() }
        let outline = PDFOutlineKeyView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(outline)
        #expect(window.makeFirstResponder(outline))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = key

        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        #expect(controller.routeOutlineGlobalKeyEvent(event))
        #expect(delegate.commands == [command])
        #expect(delegate.reader.actions.isEmpty)
        event.repeats = true
        #expect(controller.routeOutlineGlobalKeyEvent(event))
        let commands = ["n", "N"].contains(key) ? [command, command] : [command]
        #expect(delegate.commands == commands)
        event.eventType = .keyUp
        #expect(!controller.routeOutlineGlobalKeyEvent(event))
        #expect(delegate.commands == commands)
    }

    @Test(arguments: ["j", "k", "h", "l", "g", "G", "z", "d", "u", "f", "b", " ", "=", "m", "a", "i", "v", "y", "c"])
    func outlineNeverFallsThroughToReaderMovementsOrTextActions(key: String) {
        let window = makeWindow()
        defer { window.close() }
        let outline = PDFOutlineKeyView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(outline)
        #expect(window.makeFirstResponder(outline))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = key

        #expect(!controller.routeKeyEvent(event))
        #expect(!controller.routeOutlineGlobalKeyEvent(event))
        #expect(delegate.commands.isEmpty)
        #expect(delegate.reader.actions.isEmpty)
    }

    @Test(arguments: [false, true])
    func changingReaderCancelsTabOverviewOnItsStartingReader(active: Bool) throws {
        let controller = KeyboardController(
            tabPageOverviewDelay: active ? 0.001 : 10,
            installsKeyMonitor: false,
            installsOpenURLObserver: false,
            notificationCenter: notificationCenter
        )
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        let startingReader = delegate.reader
        #expect(controller.handleKeyEvent(keyEvent(.keyDown, key: "\t", keyCode: 48)))
        if active {
            try waitForPageOverview(startingReader)
        }

        delegate.reader = RecordingKeyboardReaderController()
        #expect(!controller.handleKeyEvent(keyEvent(.keyUp, key: "\t", keyCode: 48)))

        #expect(startingReader.actions == (active ? [.beginPageOverview, .cancelPageOverview] : []))
        #expect(delegate.reader.actions.isEmpty)
        #expect(delegate.commands.isEmpty)
    }

    @Test
    func standaloneUpdateWindowKeysRemainAvailableToItsOwnHandler() {
        let readerWindow = makeWindow()
        let updateWindow = makeWindow()
        defer { readerWindow.close(); updateWindow.close() }
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = readerWindow
        let event = WindowKeyboardEvent()
        event.targetWindow = updateWindow

        for key in ["j", "k", "\t", "\u{1b}", "r", "u", "o", "l", "c"] {
            event.key = key
            for type: NSEvent.EventType in [.keyDown, .keyUp] {
                event.eventType = type
                #expect(!controller.routeKeyEvent(event))
            }
        }
        #expect(delegate.commands.isEmpty)
        #expect(delegate.reader.actions.isEmpty)
        #expect(delegate.focusSwitches == 0)
        #expect(delegate.readerFocusRequests == 0)
    }

    @Test
    func readerWindowAndTextInputOwnershipAreCheckedBeforeAI() {
        let readerWindow = makeWindow()
        let settingsWindow = makeWindow()
        defer { readerWindow.close(); settingsWindow.close() }
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = readerWindow
        delegate.reader.isAIInteractionActive = true
        delegate.reader.aiKeyResult = true
        let event = WindowKeyboardEvent()
        event.targetWindow = settingsWindow

        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.reader.actions.isEmpty)
        let editor = NSTextView()
        readerWindow.contentView?.addSubview(editor)
        #expect(readerWindow.makeFirstResponder(editor))
        event.targetWindow = readerWindow
        #expect(!controller.routeKeyEvent(event))
        #expect(delegate.reader.actions.isEmpty)

        #expect(readerWindow.makeFirstResponder(nil))
        #expect(controller.routeKeyEvent(event))
        #expect(delegate.reader.actions == [.aiKey])
        #expect(delegate.commands.isEmpty)
    }

    @Test
    func emptyReaderStillRoutesOpenKey() {
        let window = makeWindow()
        defer { window.close() }
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        delegate.hasActiveReader = false
        let event = WindowKeyboardEvent()
        event.targetWindow = window
        event.key = "o"

        #expect(controller.routeKeyEvent(event))
        #expect(delegate.commands == [.open])
    }

    @Test
    func conversationInputKeepsTypingAndEscapeDismissal() {
        let window = makeWindow()
        defer { window.close() }
        let reader = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = reader
        let overlay = NSView(frame: reader.bounds)
        let editor = NSTextView(frame: overlay.bounds)
        overlay.addSubview(editor)
        reader.addSubview(overlay)
        reader.aiInteraction.conversationOverlay = overlay
        reader.aiInteraction.activeConversationModel = AIConversationPopoverModel(context: AIExplanationContext(
            selectedText: "test", currentParagraph: nil, nearbyText: "test", fileName: "test.pdf", pageNumbers: [1]
        ))
        #expect(window.makeFirstResponder(editor))
        let controller = KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false, notificationCenter: notificationCenter)
        let delegate = RecordingKeyboardDelegate()
        controller.delegate = delegate
        delegate.readerWindow = window
        delegate.overrideReader = reader
        let event = WindowKeyboardEvent()
        event.targetWindow = window

        #expect(!controller.routeKeyEvent(event))
        #expect(window.firstResponder === editor)
        #expect(delegate.commands.isEmpty)
        event.key = "\u{1b}"
        #expect(controller.routeKeyEvent(event))
        #expect(!reader.isAIInteractionActive)
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    private func waitForPageOverview(_ reader: RecordingKeyboardReaderController) throws {
        let deadline = Date().addingTimeInterval(1)
        while !reader.isPageOverviewActive, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: deadline)
        }
        try #require(reader.isPageOverviewActive)
    }

    private func keyEvent(
        _ type: NSEvent.EventType,
        key: String,
        keyCode: UInt16,
        isRepeat: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}

private final class WindowKeyboardEvent: NSEvent {
    var targetWindow: NSWindow?
    var key = "j"
    var flags: NSEvent.ModifierFlags = []
    var physicalKeyCode: UInt16 = 38
    var eventType: NSEvent.EventType = .keyDown
    var repeats = false
    override var window: NSWindow? { targetWindow }
    override var type: NSEvent.EventType { eventType }
    override var modifierFlags: NSEvent.ModifierFlags { flags }
    override var charactersIgnoringModifiers: String? { key }
    override var keyCode: UInt16 { physicalKeyCode }
    override var isARepeat: Bool { repeats }
}

@MainActor
private final class RecordingKeyboardDelegate: KeyboardControllerDelegate {
    var reader = RecordingKeyboardReaderController()
    var overrideReader: ReaderController?
    var hasActiveReader = true
    var readerWindow: NSWindow?
    var hasBlockingReaderPresentation = false
    private(set) var focusSwitches = 0
    private(set) var readerFocusRequests = 0
    private(set) var commands: [VimCommand] = []
    private(set) var openedURLs: [URL] = []

    var activeReaderController: ReaderController? {
        hasActiveReader ? overrideReader ?? reader : nil
    }

    func handleVimCommand(_ command: VimCommand) {
        commands.append(command)
    }

    func switchReadingFocus() { focusSwitches += 1 }

    func focusReaderContent() { readerFocusRequests += 1 }

    func open(urls: [URL]) {
        openedURLs.append(contentsOf: urls)
    }
}

@MainActor
private final class RecordingKeyboardReaderController: ReaderController {
    var isAIInteractionActive = false
    var hasNavigableTextSelection = false
    var hasSearchTextTarget = false
    var isPageOverviewActive = false
    var deleteHighlightsResult = false
    var aiKeyResult = false
    var textSelectionKeyResult = false
    var onBeginPageOverview: (() -> Void)?
    private(set) var actions: [Action] = []

    func snapshot() -> ReaderSnapshot? { nil }

    func focus() {}

    func beginPageOverview() -> Bool {
        actions.append(.beginPageOverview)
        isPageOverviewActive = true
        onBeginPageOverview?()
        return true
    }

    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool {
        actions.append(.movePageOverview(navigation))
        return true
    }

    func finishPageOverview() {
        actions.append(.finishPageOverview)
        isPageOverviewActive = false
    }

    func cancelPageOverview() {
        actions.append(.cancelPageOverview)
        isPageOverviewActive = false
    }

    func beginSearchCommand() {
        actions.append(.beginSearch)
    }

    func handleAIKeyEvent(_ event: NSEvent) -> Bool {
        actions.append(.aiKey)
        return aiKeyResult
    }

    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool { false }

    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool { textSelectionKeyResult }

    func vimDeleteHighlightsForSelection() -> Bool {
        actions.append(.deleteHighlights)
        return deleteHighlightsResult
    }

    func vimScroll(x: CGFloat, y: CGFloat) {}

    func vimMoveByPage(_ delta: Int) {}

    func vimGoToFirstPage() {}

    func vimGoToLastPage() {}

    func vimGoToPage(_ pageNumber: Int) {}

    func vimGoToDestination(_ destination: PDFDestination) {}

    func vimJumpBack() {}

    func vimJumpForward() {}

    func vimSearchNext() {}

    func vimSearchPrevious() {}

    func vimMaterializeSearchSelection() {}

    func vimCopySelection() {}

    func vimHighlightSelection(color: NSColor) {}

    func vimExplainSelectedHighlight() {}

    func vimStartAIConversation() {}

    func vimZoom(by factor: CGFloat) {}

    func vimZoomToPageFit() {}

    func vimZoomToFit() {}

    enum Action: Equatable {
        case beginPageOverview
        case movePageOverview(PageOverviewNavigation)
        case finishPageOverview
        case cancelPageOverview
        case beginSearch
        case deleteHighlights
        case aiKey
    }
}

@MainActor
private final class KeyboardFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

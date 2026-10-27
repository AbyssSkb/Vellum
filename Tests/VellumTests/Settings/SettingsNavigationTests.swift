@preconcurrency import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("Settings navigation", .serialized)
@MainActor
struct SettingsNavigationTests {
    @Test
    func sidebarAndControlsBrowseWithoutChangingPreferences() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()

        #expect(try fixture.press("j"))
        #expect(fixture.navigation.page == .reading)
        #expect(try fixture.press("j"))
        #expect(fixture.navigation.page == .dictionary)
        #expect(try fixture.press("k"))
        #expect(fixture.navigation.page == .reading)
        try await fixture.ready()
        #expect(try fixture.press("l"))
        #expect(fixture.navigation.rowID == "toggle-row")
        #expect(fixture.navigation.level == .rows)
        #expect(fixture.navigation.focusedControlID == "toggle")
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(try fixture.press("j"))
        #expect(fixture.navigation.rowID == "choices-row")
        #expect(["first-choice", "second-choice"].contains(fixture.navigation.focusedControlID ?? ""))
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(try fixture.press("k"))
        #expect(fixture.navigation.rowID == "toggle-row")
        #expect(fixture.navigation.focusedControlID == "toggle")
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(!fixture.model.value)
        #expect(fixture.model.actions.isEmpty)
        #expect(try fixture.press("h"))
        #expect(fixture.navigation.isSidebarFocused)
        #expect(try fixture.press("l"))
        #expect(fixture.navigation.focusedControlID == "toggle")
        #expect(try fixture.press("\u{1b}"))
        #expect(fixture.navigation.isSidebarFocused)
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(fixture.navigation.focusedControlID == nil)
    }

    @Test
    func switchesActivateWithOneKeyAndIgnoreRepeatedActivation() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("toggle-row")
        #expect(fixture.navigation.focusedControlID == "toggle")
        #expect(fixture.navigation.focusedRowID == nil)

        #expect(try fixture.press(" "))
        #expect(fixture.model.value)
        #expect(fixture.navigation.level == .rows)
        #expect(try fixture.press(" ", isRepeat: true))
        #expect(fixture.model.value)
        #expect(try fixture.press("l"))
        #expect(fixture.model.value)
        #expect(try fixture.press("\r"))
        #expect(!fixture.model.value)
        #expect(try fixture.press("\r", isRepeat: true))
        #expect(!fixture.model.value)
        #expect(try fixture.press("j"))
        #expect(fixture.navigation.rowID == "choices-row")
    }

    @Test
    func directionsOnlyMoveChoiceFocusAndActivationChangesTheSelection() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("choices-row")
        #expect(fixture.navigation.controlID == "first-choice")
        #expect(try fixture.press("l"))
        #expect(fixture.navigation.controlID == "second-choice")
        #expect(fixture.model.choice == 0)
        #expect(try fixture.press("l", isRepeat: true))
        #expect(fixture.navigation.controlID == "second-choice")
        #expect(fixture.model.actions.isEmpty)
        #expect(try fixture.press("h"))
        #expect(fixture.navigation.controlID == "first-choice")
        #expect(fixture.model.choice == 0)
        #expect(try fixture.press("l"))
        #expect(try fixture.press(" "))
        #expect(fixture.model.choice == 1)
        #expect(fixture.model.actions == ["second"])
        #expect(try fixture.press("h"))
        #expect(fixture.model.choice == 1)
        #expect(try fixture.press("\u{1b}"))
        #expect(try fixture.press("l"))
        #expect(fixture.navigation.controlID == "first-choice")
        #expect(fixture.model.choice == 1)
    }

    @Test
    func actionButtonsMoveHorizontallyWithoutExecuting() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("actions-row")
        #expect(fixture.navigation.controlID == "open-log")
        #expect(try fixture.press("l"))
        #expect(fixture.navigation.controlID == "clear-log")
        #expect(try fixture.press("l"))
        #expect(fixture.navigation.controlID == "clear-log")
        #expect(fixture.model.actions.isEmpty)
        #expect(try fixture.press("h"))
        #expect(fixture.navigation.controlID == "open-log")
        #expect(fixture.model.actions.isEmpty)
        #expect(try fixture.press("\r"))
        #expect(fixture.model.actions == ["open"])
        #expect(try fixture.press("l"))
        #expect(try fixture.press(" "))
        #expect(fixture.model.actions == ["open", "clear"])
        #expect(try fixture.press(" ", isRepeat: true))
        #expect(fixture.model.actions == ["open", "clear"])
        #expect(try fixture.press("j"))
        #expect(fixture.navigation.rowID == "text-row")
    }

    @Test
    func disabledControlsAreSkippedWithoutChangingThePreference() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("choices-row")
        #expect(fixture.navigation.controlID == "first-choice")

        fixture.model.firstChoiceEnabled = false
        try await waitForTestCondition("Disabling the focused option keeps focus in the same setting") {
            fixture.host.layoutSubtreeIfNeeded()
            return fixture.anchor("first-choice")?.enabled == false
                && fixture.navigation.rowID == "choices-row"
                && fixture.navigation.controlID == "second-choice"
        }
        #expect(fixture.model.actions.isEmpty)
        #expect(fixture.model.choice == 0)
        #expect(try fixture.press("\r"))
        #expect(fixture.model.choice == 1)
        #expect(fixture.model.actions == ["second"])

        fixture.model.secondChoiceEnabled = false
        do {
            try await waitForTestCondition("A setting with no enabled controls keeps focus on its row") {
                fixture.host.layoutSubtreeIfNeeded()
                return fixture.anchor("second-choice")?.enabled == false
                    && fixture.navigation.level == .rows
                    && fixture.navigation.controlID == nil
                    && fixture.navigation.rowID == "choices-row"
                    && fixture.window.firstResponder === fixture.anchor("choices-row")
            }
        } catch {
            print("Disabled choices: level=\(fixture.navigation.level), row=\(fixture.navigation.rowID ?? "nil"), control=\(fixture.navigation.controlID ?? "nil"), responder=\(String(describing: fixture.window.firstResponder)), expectedRow=\(String(describing: fixture.anchor("choices-row"))), firstEnabled=\(String(describing: fixture.anchor("first-choice")?.enabled)), secondEnabled=\(String(describing: fixture.anchor("second-choice")?.enabled))")
            throw error
        }
        #expect(try fixture.press("\r"))
        #expect(fixture.navigation.level == .rows)
        #expect(fixture.navigation.focusedRowID == "choices-row")
        #expect(fixture.navigation.focusedControlID == nil)
        #expect(fixture.model.actions == ["second"])
        #expect(try fixture.press("j"))
        #expect(fixture.navigation.rowID == "actions-row")
    }

    @Test
    func queuedDisabledRecoveryDoesNotOverrideLaterUserNavigation() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("choices-row")
        let control = try #require(fixture.anchor("first-choice"))
        control.enabled = false
        fixture.navigation.controlBecameUnavailable(control)

        try await fixture.monitoredPress("j") { fixture.navigation.rowID == "actions-row" }
        await nextTestMainQueueTurn()
        #expect(fixture.navigation.rowID == "actions-row")
        #expect(fixture.model.actions.isEmpty)
    }

    @Test
    func clickingAButtonKeepsVerticalNavigationOnControls() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        let toggle = try #require(fixture.anchor("toggle"))
        let bounds = toggle.convert(toggle.bounds, to: nil)
        let point = NSPoint(x: bounds.midX, y: bounds.midY)
        let screen = try #require(NSScreen.screens.first)
        try #require(screen.visibleFrame.contains(fixture.window.convertPoint(toScreen: point)))
        let monitor = try #require(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                if event.window === fixture.window { #expect(event.locationInWindow == point) }
            }
            return event
        })
        defer { NSEvent.removeMonitor(monitor) }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: NSPoint(x: bounds.midX, y: bounds.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            #expect(event.window === fixture.window)
            NSApp.postEvent(event, atStart: false)
        }
        try await waitForTestCondition("Clicking a switch focuses and changes that setting", dispatchAppKitEvents: true) {
            fixture.model.value && fixture.navigation.controlID == "toggle"
        }
        #expect(try fixture.press("j"))
        #expect(fixture.navigation.rowID == "choices-row")
        #expect(fixture.model.value)
    }

    @Test(arguments: ["text", "secure", "editor"])
    func fieldsHaveOrdinaryFocusBeforeEditingAndEscapeReturnsToTheSameField(_ field: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("\(field)-row")
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(fixture.navigation.focusedControlID == field)
        #expect(fixture.window.firstResponder === fixture.anchor(field))
        #expect(fixture.navigation.level == .rows)
        #expect(try fixture.press(" "))
        #expect(fixture.window.firstResponder === fixture.anchor(field))
        #expect(fixture.model.text(for: field).isEmpty)
        #expect(try fixture.press("\r"))
        let editor = try await fixture.readyEditor(field)
        #expect(fixture.navigation.level == .controls)
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(fixture.navigation.focusedControlID == field)

        for key in ["h", "j", "k", "l", " "] {
            let event = try fixture.event(key)
            #expect(!fixture.navigation.handle(event, in: fixture.window))
            editor.keyDown(with: event)
        }
        try await waitForTestCondition("The \(field) binding receives normal text input") {
            fixture.model.text(for: field) == "hjkl "
        }
        if field == "editor" {
            let event = try fixture.event("\r")
            #expect(!fixture.navigation.handle(event, in: fixture.window))
            editor.keyDown(with: event)
            try await waitForTestCondition("Return adds a line to the multiline editor") {
                fixture.model.editor == "hjkl \n"
            }
        }
        #expect(try fixture.press("\u{1b}"))
        #expect(fixture.navigation.level == .rows)
        #expect(fixture.navigation.rowID == "\(field)-row")
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(fixture.navigation.focusedControlID == field)
        #expect(fixture.window.firstResponder === fixture.anchor(field))
        if field != "editor" {
            #expect(try fixture.press("j"))
            let next = field == "text" ? "secure" : "editor"
            #expect(fixture.navigation.focusedControlID == next)
            #expect(fixture.window.firstResponder === fixture.anchor(next))
        }
        #expect(try fixture.press("\u{1b}"))
        #expect(fixture.navigation.isSidebarFocused)
    }

    @Test
    func escapeLeavesMarkedTextToTheInputMethod() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("text-row")
        #expect(try fixture.press("\r"))
        let editor = try await fixture.readyEditor("text")
        editor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        #expect(try !fixture.press("\u{1b}"))
        #expect(fixture.window.firstResponder === editor)
        #expect(fixture.navigation.level == .controls)
        editor.unmarkText()
        #expect(try fixture.press("\u{1b}"))
        #expect(fixture.navigation.level == .rows)
    }

    @Test
    func nativeFieldFocusAndTabStayInSyncWithNavigation() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        let field = try #require(fixture.nativeFields.first { !($0 is NSSecureTextField) })
        #expect(fixture.window.makeFirstResponder(field))
        _ = try await fixture.readyEditor("text")
        #expect(fixture.navigation.rowID == "text-row")
        #expect(fixture.navigation.controlID == "text")
        #expect(try !fixture.press("\t"))

        NSApp.postEvent(try fixture.event("\t"), atStart: false)
        _ = try await fixture.readyEditor("secure")
        #expect(fixture.navigation.rowID == "secure-row")
        #expect(fixture.navigation.controlID == "secure")
        #expect(try fixture.press("\u{1b}"))
        #expect(fixture.navigation.rowID == "secure-row")
        #expect(fixture.navigation.level == .rows)
    }

    @Test
    func clickingAnAlreadyEditedFieldKeepsEscapeOnThatField() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        try fixture.enterRow("text-row")
        #expect(try fixture.press("\r"))
        _ = try await fixture.readyEditor("text")
        let field = try #require(fixture.anchor("text"))
        let bounds = field.convert(field.bounds, to: nil)
        for _ in 0..<2 {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type,
                    location: NSPoint(x: bounds.midX, y: bounds.midY), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.postEvent(event, atStart: false)
            }
        }
        while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
        #expect(fixture.navigation.level == .controls)
        try await fixture.monitoredPress("\u{1b}") {
            fixture.navigation.level == .rows && fixture.navigation.focusedControlID == "text"
                && fixture.window.firstResponder === field
        }
        #expect(!fixture.navigation.isSidebarFocused)
    }

    @Test
    func nativeSidebarTabOrderFollowsThePageSelectedWithVim() async throws {
        let fixture = try AppFixture()
        defer { fixture.close() }
        try await fixture.ready()
        try await fixture.post("j") { fixture.navigation.page == .reading }
        try await fixture.post("j") { fixture.navigation.page == .dictionary }
        try await fixture.post("\t", modifiers: .shift) {
            fixture.navigation.page == .reading && fixture.navigation.isSidebarFocused
        }
        try await fixture.post("\t") {
            fixture.navigation.page == .dictionary && fixture.navigation.isSidebarFocused
        }
        #expect(fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.english.rawValue)
        #expect(fixture.preferences.defaults.object(forKey: AppPreferenceKeys.dictionaryPath) == nil)
    }

    @Test
    func tabFocusActivatesThatOptionInsteadOfThePreviousSelection() async throws {
        let fixture = try AppFixture()
        defer { fixture.close() }
        try await fixture.ready()
        try await fixture.post("l") {
            fixture.navigation.rowID == "app-language"
                && fixture.navigation.controlID == "en"
                && fixture.window.firstResponder !== fixture.anchors.first { $0.id == "app-language" && $0.role == .row }
        }
        #expect(fixture.navigation.focusedControlID == "en")
        #expect(fixture.navigation.focusedRowID == nil)
        try await fixture.post("\t") { fixture.navigation.controlID == "zh-Hans" }
        #expect(fixture.navigation.focusedControlID == "zh-Hans")
        #expect(fixture.navigation.focusedRowID == nil)
        #expect(fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.english.rawValue)
        try await fixture.post("\r") {
            fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.chinese.rawValue
        }
        try await fixture.post("j") { fixture.navigation.rowID == "restore-previous-tabs" }
    }

    @Test
    func languageDirectionsOnlyMoveFocusAndSpaceActivatesTheFocusedOption() async throws {
        let fixture = try AppFixture()
        defer { fixture.close() }
        try await fixture.ready()
        let navigation = fixture.navigation
        try await fixture.post("l") {
            navigation.level == .rows && navigation.rowID == "app-language" && navigation.controlID == "en"
        }
        #expect(fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.english.rawValue)
        try await fixture.post("h") { navigation.isSidebarFocused }
        try await fixture.post("l") { navigation.controlID == "en" }
        try await fixture.post("l") { navigation.controlID == "zh-Hans" }
        #expect(fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.english.rawValue)
        try await fixture.post("\u{1b}") { navigation.isSidebarFocused }
        try await fixture.post("l") { navigation.controlID == "zh-Hans" }
        #expect(fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.english.rawValue)
        try await fixture.post(" ") {
            fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.chinese.rawValue
        }
        try await fixture.post("h") { navigation.controlID == "en" }
        #expect(fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.chinese.rawValue)
        try await fixture.post("\r") {
            fixture.preferences.defaults.string(forKey: AppPreferenceKeys.appLanguage) == AppUILanguage.english.rawValue
        }
        try await fixture.post("j") { navigation.rowID == "restore-previous-tabs" }
        #expect(fixture.preferences.defaults.object(forKey: AppPreferenceKeys.restorePreviousTabs) == nil)
    }

    @Test
    func providerGridDirectionsFollowVisibleRowsAndColumnsWithoutChangingTheProvider() async throws {
        let defaults = UserDefaults.standard
        let presets = AIProviderPreset.presets
        let keys = [AISettingsKeys.providerSettingsSelectionID, AISettingsKeys.providerID,
                    AISettingsKeys.baseURL, AISettingsKeys.model, AISettingsKeys.apiKey]
            + presets.flatMap { [AISettingsKeys.baseURLKey(for: $0.id), AISettingsKeys.modelKey(for: $0.id),
                                 AISettingsKeys.apiKeyKey(for: $0.id), AISettingsKeys.conversationBaseURLKey(for: $0.id),
                                 AISettingsKeys.conversationAPIKeyKey(for: $0.id)] }
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }
        defaults.set(presets[0].id, forKey: AISettingsKeys.providerSettingsSelectionID)
        let fixture = try AppFixture()
        defer { fixture.close() }
        try await fixture.ready()
        for page in SettingsPage.allCases.dropFirst().prefix(while: { $0 != .aiExplanation }) {
            try await fixture.post("j") { fixture.navigation.page == page }
        }
        try await waitForTestCondition("The six provider cards are mounted in the real settings grid", dispatchAppKitEvents: true) {
            fixture.host.layoutSubtreeIfNeeded()
            return presets.allSatisfy { preset in
                fixture.anchors.contains { $0.page == .aiProviders && $0.id == "provider-\(preset.id)" && $0.role == .control }
            }
        }
        let cards = try presets.map { preset in
            try #require(fixture.anchors.first { $0.id == "provider-\(preset.id)" && $0.role == .control })
        }
        let positions = cards.map { $0.convert($0.bounds, to: nil) }
        #expect(abs(positions[0].maxY - positions[1].maxY) < 3)
        #expect(abs(positions[0].midX - positions[2].midX) < 3)
        #expect(positions[2].maxY < positions[0].minY)
        try await fixture.post("l") { fixture.navigation.controlID == "provider-\(presets[0].id)" }
        try await fixture.post("j") { fixture.navigation.controlID == "provider-\(presets[2].id)" }
        try await fixture.post("l") { fixture.navigation.controlID == "provider-\(presets[3].id)" }
        try await fixture.post("l") { fixture.navigation.controlID == "provider-\(presets[3].id)" }
        try await fixture.post("k") { fixture.navigation.controlID == "provider-\(presets[1].id)" }
        try await fixture.post("h") { fixture.navigation.controlID == "provider-\(presets[0].id)" }
        #expect(defaults.string(forKey: AISettingsKeys.providerSettingsSelectionID) == presets[0].id)
        try await fixture.post("j") { fixture.navigation.controlID == "provider-\(presets[2].id)" }
        try await fixture.post(" ") { defaults.string(forKey: AISettingsKeys.providerSettingsSelectionID) == presets[2].id }
    }

    @Test
    func movingUpFromTheTopOfReleaseNotesReturnsToThePreviousSetting() async throws {
        let fixture = try AppFixture()
        defer { fixture.close() }
        try await fixture.ready()
        for page in SettingsPage.allCases.dropFirst() {
            try await fixture.post("j") { fixture.navigation.page == page }
        }
        try await waitForTestCondition("About settings are mounted before browsing their targets", dispatchAppKitEvents: true) {
            fixture.host.layoutSubtreeIfNeeded()
            return fixture.anchors.contains { $0.page == .about && $0.id == "automatic-updates" && $0.role == .row }
        }
        try await fixture.post("l") { fixture.navigation.controlID == "automatic-updates" }
        try await fixture.post("j") { fixture.navigation.controlID == "check-now" }
        try await fixture.post("j") { fixture.navigation.rowID == "release-notes" }
        let notes = try #require(fixture.anchors.first { $0.id == "release-notes" && $0.role == .reading })
        let scroll = try #require(notes.enclosingScrollView)
        let document = try #require(scroll.documentView)
        let top = NSPoint(x: 0, y: document.isFlipped ? 0 : max(0, document.bounds.height - scroll.contentView.bounds.height))
        scroll.contentView.setBoundsOrigin(top)
        scroll.reflectScrolledClipView(scroll.contentView)

        try await fixture.post("k") { fixture.navigation.focusedControlID == "check-now" }
    }

    @MainActor
    private final class AppFixture {
        let preferences: TestPreferences
        let navigation = SettingsNavigation()
        let window: NSWindow
        let host: NSHostingView<AnyView>

        init() throws {
            preferences = try TestPreferences()
            preferences.defaults.set(AppUILanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 640),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host = NSHostingView(rootView: AnyView(AISettingsView(navigation: navigation)
                .defaultAppStorage(preferences.defaults)))
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        var anchors: [SettingsAnchorView] {
            func collect(in view: NSView) -> [SettingsAnchorView] {
                if let anchor = view as? SettingsAnchorView { return [anchor] }
                return view.subviews.flatMap { collect(in: $0) }
            }
            return collect(in: host)
        }

        func ready() async throws {
            try await waitForTestCondition("The actual settings sidebar is mounted in its key window", dispatchAppKitEvents: true) {
                self.host.layoutSubtreeIfNeeded()
                return self.window.isKeyWindow && self.anchors.filter { $0.role == .sidebar }.count == SettingsPage.allCases.count
            }
            navigation.focusSidebar()
            try await waitForTestCondition("General has native keyboard focus", dispatchAppKitEvents: true) {
                self.window.firstResponder != nil && self.window.firstResponder !== self.navigation.keyboardView
            }
        }

        func post(_ key: String, modifiers: NSEvent.ModifierFlags = [], until condition: () -> Bool) async throws {
            let codes: [String: UInt16] = ["h": 4, "j": 38, "k": 40, "l": 37, " ": 49, "\t": 48, "\r": 36, "\u{1b}": 53]
            let previousPage = navigation.page
            let previousResponder = String(describing: window.firstResponder)
            let characters = key == "\t" && modifiers.contains(.shift) ? "\u{19}" : key
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: codes[key] ?? 0))
            NSApp.postEvent(event, atStart: false)
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            do {
                try await waitForTestCondition("The actual settings window handles \(key.debugDescription), modifiers=\(modifiers.rawValue)", dispatchAppKitEvents: true, condition)
            } catch {
                let responder = window.firstResponder as? NSView
                print("Settings event \(key.debugDescription), modifiers=\(modifiers.rawValue): page \(previousPage.rawValue) -> \(navigation.page.rawValue), level=\(navigation.level), fullKeyboardAccess=\(NSApp.isFullKeyboardAccessEnabled), key=\(window.isKeyWindow), responder \(previousResponder) -> \(String(describing: responder)), next=\(String(describing: responder?.nextValidKeyView)), previous=\(String(describing: responder?.previousValidKeyView))")
                throw error
            }
        }

        func close() {
            host.rootView = AnyView(EmptyView())
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
            preferences.cleanup()
        }
    }

    @Test
    func eventsFromAnotherWindowOrWithCommandModifiersRemainNative() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.ready()
        #expect(try !fixture.press("j", modifiers: .command))
        #expect(try !fixture.press("j", modifiers: .shift))
        #expect(fixture.navigation.page == .general)

        let other = NSWindow(contentRect: NSRect(x: 30, y: 30, width: 200, height: 150), styleMask: .titled, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        let otherEvent = try fixture.event("j", window: other)
        #expect(!fixture.navigation.handle(otherEvent, in: fixture.window))
        other.makeKeyAndOrderFront(nil)
        try await waitForTestCondition("The other window takes keyboard focus", dispatchAppKitEvents: true) { other.isKeyWindow }
        #expect(try !fixture.press("j"))
        fixture.window.close()
        #expect(try !fixture.press("j"))
        #expect(fixture.navigation.page == .general)
    }

    @Test
    func readingRegionRespondsToTheWindowMonitorAndMouseFocus() async throws {
        let fixture = Fixture(readingOnly: true)
        defer { fixture.close() }
        try await fixture.ready()
        let notes = try #require(fixture.anchor("notes-row"))
        let scroll = try #require(notes.enclosingScrollView)
        #expect(scroll.documentView!.bounds.height > scroll.contentView.bounds.height)

        try await fixture.monitoredPress("l") { fixture.navigation.level == .reading }
        #expect(fixture.navigation.focusedRowID == "notes-row")
        #expect(fixture.navigation.focusedControlID == nil)
        let originalY = scroll.documentVisibleRect.minY
        try await fixture.monitoredPress("j") {
            abs(scroll.documentVisibleRect.minY - originalY) > 2
        }
        #expect(fixture.navigation.level == .reading)
        try await fixture.monitoredPress("\u{1b}") { fixture.navigation.isSidebarFocused }

        let visible = notes.convert(notes.bounds, to: nil)
            .intersection(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        #expect(!visible.isEmpty)
        let location = NSPoint(x: visible.midX, y: visible.midY)
        // Queue the complete click so native mouse tracking never waits for a release.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            NSApp.postEvent(event, atStart: false)
        }
        try await waitForTestCondition("Clicking notes restores their reading focus", dispatchAppKitEvents: true) {
            fixture.navigation.level == .reading && fixture.navigation.rowID == "notes-row"
        }
        #expect(!fixture.model.value)
        #expect(fixture.model.actions.isEmpty)
    }

    @Test
    func aDirectionKeyContinuesIntoLazyGridItemsWithoutChangingAnyOption() async throws {
        let fixture = Fixture(lazyGrid: true)
        defer { fixture.close() }
        try await fixture.ready()
        try await fixture.monitoredPress("l") { fixture.navigation.controlID == "grid-0" }
        let initial = Set(fixture.gridItemIndices)
        let lastLeft = try #require(initial.filter { $0.isMultiple(of: 2) }.max())
        #expect(lastLeft < 298)
        for index in stride(from: 2, through: lastLeft + 2, by: 2) {
            try await fixture.monitoredPress("j") { fixture.navigation.controlID == "grid-\(index)" }
        }
        #expect(!initial.contains(lastLeft + 2))
        #expect(fixture.model.actions.isEmpty)
    }

    @MainActor
    private final class Model: ObservableObject {
        @Published var value = false
        @Published var choice = 0
        @Published var actions: [String] = []
        @Published var firstChoiceEnabled = true
        @Published var secondChoiceEnabled = true
        @Published var text = ""
        @Published var secure = ""
        @Published var editor = ""

        func text(for id: String) -> String {
            switch id {
            case "secure": secure
            case "editor": editor
            default: text
            }
        }
    }

    @MainActor
    private struct Content: View {
        @ObservedObject var model: Model
        @FocusState private var textFocused: Bool
        @FocusState private var secureFocused: Bool
        @FocusState private var editorFocused: Bool

        var body: some View {
            VStack(spacing: 18) {
                HStack {
                    Text("Automatic pronunciation")
                    Spacer()
                    Button("Toggle") { model.value.toggle() }
                        .settingsControl("toggle") { model.value.toggle() }
                }
                .padding(8)
                .settingsRow("toggle-row")

                HStack {
                    Text("Accent")
                    Spacer()
                    Button("First") { model.choice = 0; model.actions.append("first") }
                        .settingsControl("first-choice", isSelected: model.choice == 0) { model.choice = 0; model.actions.append("first") }
                        .disabled(!model.firstChoiceEnabled)
                    Button("Second") { model.choice = 1; model.actions.append("second") }
                        .settingsControl("second-choice", isSelected: model.choice == 1) { model.choice = 1; model.actions.append("second") }
                        .disabled(!model.secondChoiceEnabled)
                }
                .padding(8)
                .settingsRow("choices-row")

                HStack {
                    Text("Diagnostics")
                    Spacer()
                    Button("Open") { model.actions.append("open") }
                        .settingsControl("open-log") { model.actions.append("open") }
                    Button("Clear") { model.actions.append("clear") }
                        .settingsControl("clear-log") { model.actions.append("clear") }
                }
                .padding(8)
                .settingsRow("actions-row")

                TextField("Endpoint", text: $model.text)
                    .settingsField("text", focused: $textFocused)
                    .padding(8)
                    .settingsRow("text-row")
                SecureField("API key", text: $model.secure)
                    .settingsField("secure", focused: $secureFocused)
                    .padding(8)
                    .settingsRow("secure-row")
                TextEditor(text: $model.editor)
                    .settingsField("editor", focused: $editorFocused)
                    .frame(height: 100)
                    .padding(8)
                    .settingsRow("editor-row")
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    private struct ReadingContent: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<60) { index in
                        Text("Release note \(index): a readable description of the current version.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .settingsReadingArea("notes-row")
            }
        }
    }

    private struct LazyGridContent: View {
        @ObservedObject var model: Model

        var body: some View {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(0..<300) { index in
                        Button("Model \(index)") { model.actions.append("\(index)") }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .settingsControl("grid-\(index)", isSelected: index == 0) { model.actions.append("\(index)") }
                    }
                }
                .settingsRow("grid")
                .padding(20)
            }
        }
    }

    @MainActor
    private final class FixtureWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    @MainActor
    private final class Fixture {
        let model = Model()
        let navigation = SettingsNavigation()
        let window: NSWindow
        let host: NSHostingView<AnyView>
        private let readingOnly: Bool
        private let lazyGrid: Bool

        init(readingOnly: Bool = false, lazyGrid: Bool = false) {
            self.readingOnly = readingOnly
            self.lazyGrid = lazyGrid
            _ = NSApplication.shared
            // The command-line test host must opt in before it can own a key window.
            NSApp.setActivationPolicy(.accessory)
            window = FixtureWindow(contentRect: NSRect(x: 60, y: 60, width: 620, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let content = readingOnly ? AnyView(ReadingContent())
                : lazyGrid ? AnyView(LazyGridContent(model: model)) : AnyView(Content(model: model))
            host = NSHostingView(rootView: AnyView(content
                .environmentObject(navigation)
                .background(SettingsKeyboardBridge(navigation: navigation))))
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func ready() async throws {
            do {
                try await waitForTestCondition("Settings controls are mounted in an active key window", dispatchAppKitEvents: true) {
                    self.host.layoutSubtreeIfNeeded()
                    let mounted = self.lazyGrid ? self.anchor("grid-0") != nil : self.readingOnly
                        ? self.anchor("notes-row")?.page == self.navigation.page
                        : self.anchor("editor-row")?.page == self.navigation.page && self.nativeFields.count >= 2
                    return NSApp.isActive && self.window.isKeyWindow && mounted
                }
            } catch {
                let mountedAnchors = descendants(of: SettingsAnchorView.self, in: host).map { "\($0.id):\($0.page.rawValue)" }
                print("Settings fixture: key=\(window.isKeyWindow), visible=\(window.isVisible), active=\(NSApp.isActive), anchors=\(mountedAnchors), fields=\(nativeFields.count), responder=\(String(describing: window.firstResponder))")
                throw error
            }
            navigation.focusSidebar()
            await nextTestMainQueueTurn()
            let screen = try #require(NSScreen.screens.first)
            window.setFrameTopLeftPoint(NSPoint(x: screen.frame.minX, y: screen.frame.maxY))
            try #require(window.frame.minX == screen.frame.minX && window.frame.maxY == screen.frame.maxY)
        }

        func anchor(_ id: String) -> SettingsAnchorView? {
            descendants(of: SettingsAnchorView.self, in: host).first { $0.id == id }
        }

        var nativeFields: [NSTextField] {
            descendants(of: NSTextField.self, in: host).filter(\.isEditable)
        }

        var gridItemIndices: [Int] {
            descendants(of: SettingsAnchorView.self, in: host)
                .filter { $0.role == .control && $0.id.hasPrefix("grid-") }
                .compactMap { Int($0.id.dropFirst(5)) }
        }

        func enterRow(_ id: String) throws {
            navigation.focusSidebar()
            #expect(try press("l"))
            for _ in 0..<8 where navigation.rowID != id { #expect(try press("j")) }
            #expect(navigation.rowID == id)
            if id == "choices-row", navigation.controlID == "second-choice" { #expect(try press("h")) }
            if id == "actions-row", navigation.controlID == "clear-log" { #expect(try press("h")) }
        }

        func readyEditor(_ id: String) async throws -> NSTextView {
            do {
                try await waitForTestCondition("The \(id) field becomes the native text editor", dispatchAppKitEvents: true) {
                    self.host.layoutSubtreeIfNeeded()
                    return self.navigation.controlID == id && (self.window.firstResponder as? NSTextView)?.isEditable == true
                }
            } catch {
                let editors = nativeFields.map { "\(type(of: $0)): \($0.placeholderString ?? ""), editing=\($0.currentEditor() === window.firstResponder)" }
                print("Settings editor \(id): responder=\(String(describing: window.firstResponder)), control=\(navigation.controlID ?? "nil"), row=\(navigation.rowID ?? "nil"), fields=\(editors)")
                throw error
            }
            return try #require(window.firstResponder as? NSTextView)
        }

        func monitoredPress(_ key: String, until condition: () -> Bool) async throws {
            NSApp.postEvent(try event(key), atStart: false)
            try await waitForTestCondition("The settings window monitor handles \(key)", dispatchAppKitEvents: true, condition)
        }

        @discardableResult
        func press(_ key: String, isRepeat: Bool = false, modifiers: NSEvent.ModifierFlags = []) throws -> Bool {
            navigation.handle(try event(key, isRepeat: isRepeat, modifiers: modifiers), in: window)
        }

        func event(_ key: String, isRepeat: Bool = false, modifiers: NSEvent.ModifierFlags = [], window target: NSWindow? = nil) throws -> NSEvent {
            let codes: [String: UInt16] = ["h": 4, "j": 38, "k": 40, "l": 37, " ": 49, "\r": 36, "\t": 48, "\u{1b}": 53]
            return try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: (target ?? window).windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: isRepeat, keyCode: codes[key] ?? 0))
        }

        private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
        }

        func close() {
            host.rootView = AnyView(EmptyView())
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
        }
    }
}

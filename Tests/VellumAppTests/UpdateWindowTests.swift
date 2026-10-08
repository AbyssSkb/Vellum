import AppKit
import Testing
import VellumCore
@testable import Vellum

@Suite(.serialized)
@MainActor
struct UpdateWindowTests {
    @Test
    func vimScrollUsesCountsAndPageMotions() throws {
        let controller = makeController()
        defer { controller.dismiss() }
        let window = try #require(controller.window)
        let scroll = try #require(descendants(of: window.contentView!).compactMap { $0 as? NSScrollView }.first)
        window.contentView?.layoutSubtreeIfNeeded()
        let initial = scroll.contentView.bounds.minY

        send("j", to: window)
        #expect(abs(scroll.contentView.bounds.minY - initial - 26) < 1)
        send("4", to: window)
        send("j", to: window)
        #expect(abs(scroll.contentView.bounds.minY - initial - 130) < 1)
        send("k", to: window)
        #expect(abs(scroll.contentView.bounds.minY - initial - 104) < 1)
        send("g", to: window)
        send("g", to: window)
        #expect(scroll.contentView.bounds.minY == 0)

        send("d", modifiers: .control, to: window)
        #expect(abs(scroll.contentView.bounds.minY - scroll.contentView.bounds.height / 2) < 1)
        send("u", modifiers: .control, to: window)
        #expect(scroll.contentView.bounds.minY == 0)
        send("f", modifiers: .control, to: window)
        #expect(abs(scroll.contentView.bounds.minY - scroll.contentView.bounds.height) < 1)
        send("b", modifiers: .control, to: window)
        #expect(scroll.contentView.bounds.minY == 0)
        send("G", modifiers: .shift, to: window)
        #expect(abs(scroll.contentView.bounds.maxY - scroll.documentView!.bounds.maxY) < 1)
        send("g", to: window)
        send("g", to: window)
        #expect(scroll.contentView.bounds.minY == 0)
    }

    @Test
    func prefixesIgnoreRepeatsAndResetWhenWindowLosesFocus() throws {
        let controller = makeController()
        defer { controller.dismiss() }
        let window = try #require(controller.window)
        let scroll = try #require(descendants(of: window.contentView!).compactMap { $0 as? NSScrollView }.first)
        window.makeKey()

        send("2", to: window)
        send("2", repeating: true, to: window)
        send("j", to: window)
        #expect(abs(scroll.contentView.bounds.minY - 52) < 1)
        send("j", repeating: true, to: window)
        #expect(abs(scroll.contentView.bounds.minY - 78) < 1)
        send("k", repeating: true, to: window)
        #expect(abs(scroll.contentView.bounds.minY - 52) < 1)
        send("g", to: window)
        send("g", repeating: true, to: window)
        #expect(abs(scroll.contentView.bounds.minY - 52) < 1)
        send("g", to: window)
        #expect(scroll.contentView.bounds.minY == 0)

        send("3", to: window)
        window.resignKey()
        window.makeKey()
        send("j", to: window)
        #expect(abs(scroll.contentView.bounds.minY - 26) < 1)
        send("g", to: window)
        window.resignKey()
        window.makeKey()
        send("g", to: window)
        #expect(abs(scroll.contentView.bounds.minY - 26) < 1)
        send("g", to: window)
        #expect(scroll.contentView.bounds.minY == 0)
    }

    @Test
    func actionLettersDoNotCollideWithPendingVimInputOrRepeat() throws {
        var invocations = 0
        let action = UpdateWindowAction(title: "Restart and Update", key: "r", isPrimary: true) { invocations += 1 }
        let controller = makeController(actions: [action])
        defer { controller.dismiss() }
        let window = try #require(controller.window)
        send("g", to: window)
        send("r", to: window)
        send("2", to: window)
        send("r", to: window)
        #expect(invocations == 0)
        send("r", to: window)
        #expect(invocations == 1)
        send("r", repeating: true, to: window)
        #expect(invocations == 1)
        send("r", modifiers: .command, to: window)
        #expect(invocations == 1)
        send("\r", keyCode: 36, to: window)
        #expect(invocations == 2)
        send("\r", keyCode: 36, repeating: true, to: window)
        #expect(invocations == 2)
    }

    @Test
    func tabNavigationLetsReturnActivateTheFocusedAction() throws {
        var selected: [String] = []
        let controller = makeController(actions: [
            UpdateWindowAction(title: "Later", key: "l") { selected.append("later") },
            UpdateWindowAction(title: "Restart and Update", key: "r", isPrimary: true) { selected.append("restart") }
        ])
        defer { controller.dismiss() }
        let window = try #require(controller.window)
        send("\t", keyCode: 48, to: window)
        #expect((window.firstResponder as? NSButton)?.title == "Later")
        send("\r", keyCode: 36, to: window)
        send("\t", keyCode: 48, modifiers: .shift, to: window)
        #expect((window.firstResponder as? NSButton)?.title == "Restart and Update")
        send("\r", keyCode: 36, to: window)
        #expect(selected == ["later", "restart"])
        controller.update(UpdateWindowContent(phase: .available, currentVersion: "0.8.7", actions: [
            UpdateWindowAction(title: "Download Update", key: "u", isPrimary: true) { selected.append("download") }
        ]))
        send("\r", keyCode: 36, to: window)
        #expect(selected == ["later", "restart", "download"])
    }

    @Test
    func progressUpdatesPreserveNotesScrollAndButtonFocus() throws {
        let sections = longNotes()
        var cancellation = 0
        let actions = [UpdateWindowAction(title: "Cancel", key: "c") { cancellation = 1 }]
        var content = UpdateWindowContent(phase: .downloading, currentVersion: "0.8.7", updateVersion: "0.8.8", releaseNotes: sections, progress: 0.1, actions: actions)
        let controller = UpdateWindowController()
        controller.present(content, activate: false)
        defer { controller.dismiss() }
        let window = try #require(controller.window)
        let scroll = try #require(descendants(of: window.contentView!).compactMap { $0 as? NSScrollView }.first)
        send("8", to: window)
        send("j", to: window)
        send("\t", keyCode: 48, to: window)
        let offset = scroll.contentView.bounds.minY
        let button = window.firstResponder
        #expect(offset > 0)
        content.progress = 0.9
        content.actions = [UpdateWindowAction(title: "Cancel", key: "c") { cancellation = 2 }]
        controller.update(content)
        #expect(scroll.contentView.bounds.minY == offset)
        #expect(window.firstResponder === button)
        send("c", to: window)
        #expect(cancellation == 2)
    }

    @Test
    func compactChecksExpandForNotesWithoutMovingTheHeader() throws {
        _ = NSApplication.shared
        let controller = UpdateWindowController()
        controller.update(UpdateWindowContent(phase: .checking, currentVersion: "0.8.7"))
        defer { controller.dismiss() }
        let window = try #require(controller.window)
        let compactHeight = window.frame.height
        let top = window.frame.maxY
        let center = window.frame.midX
        let compactWidth = window.frame.width
        controller.update(UpdateWindowContent(phase: .available, currentVersion: "0.8.7", updateVersion: "0.8.8", releaseNotes: longNotes()))
        #expect(window.frame.height > compactHeight)
        #expect(window.frame.maxY == top)
        #expect(window.frame.midX == center)
        #expect(window.frame.width > compactWidth)
        controller.update(UpdateWindowContent(phase: .upToDate, currentVersion: "0.8.7"))
        #expect(window.frame.height == compactHeight)
        #expect(window.frame.maxY == top)
        #expect(window.frame.midX == center)
        #expect(window.frame.width == compactWidth)
    }

    @Test
    func latestVersionUsesACenteredCompactResultAndKeepsCloseShortcut() throws {
        _ = NSApplication.shared
        let controller = UpdateWindowController()
        defer { controller.dismiss() }
        var closes = 0
        let result = UpdateWindowContent(phase: .upToDate, currentVersion: "0.8.8", actions: [
            UpdateWindowAction(title: "Close", key: "c", isPrimary: true) { closes += 1 }
        ])
        controller.update(result)
        let window = try #require(controller.window)
        let root = try #require(window.contentView)
        root.layoutSubtreeIfNeeded()
        let views = descendants(of: root)
        let icon = try #require(views.compactMap { $0 as? NSImageView }.first)
        let button = try #require(views.compactMap { $0 as? NSButton }.first)
        #expect(abs(root.bounds.height - 232) < 0.5)
        #expect(root.bounds.width < 560)
        #expect(icon.contentTintColor == .systemGreen)
        #expect(abs(root.convert(icon.bounds, from: icon).midX - root.bounds.midX) < 0.5)
        // Native stack layout can round an odd-width button by half a point.
        #expect(abs(root.convert(button.bounds, from: button).midX - root.bounds.midX) <= 0.5)
        #expect(views.compactMap { $0 as? NSTextField }.filter { !$0.isHidden && !$0.stringValue.isEmpty }
            .allSatisfy { $0.alignment == .center })
        send("c", to: window)
        #expect(closes == 1)

        controller.update(UpdateWindowContent(phase: .ready, currentVersion: "0.8.8", updateVersion: "0.8.9", releaseNotes: longNotes()))
        controller.update(result)
        root.layoutSubtreeIfNeeded()
        let restoredButton = try #require(descendants(of: root).compactMap { $0 as? NSButton }.first)
        #expect(abs(root.convert(restoredButton.bounds, from: restoredButton).midX - root.bounds.midX) <= 0.5)
        send("c", to: window)
        #expect(closes == 2)
    }

    @Test
    func statusWidthFitsLocalizedLabelsAndActionsAndScalesProgress() throws {
        _ = NSApplication.shared
        let preference = AppPreferenceKeys.appLanguage
        let previous = UserDefaults.standard.object(forKey: preference)
        defer { UserDefaults.standard.set(previous, forKey: preference) }
        let controller = UpdateWindowController()
        defer { controller.dismiss() }
        for language in AppUILanguage.allCases {
            UserDefaults.standard.set(language.rawValue, forKey: preference)
            controller.update(UpdateWindowContent(phase: .upToDate, currentVersion: "0.8.9", actions: [
                UpdateWindowAction(title: language.text(.closeUpdate), key: "c", isPrimary: true) {}
            ]))
            let root = try #require(controller.window?.contentView)
            let compactWidth = root.bounds.width
            #expect(compactWidth >= 320 && compactWidth < 560)
            controller.update(UpdateWindowContent(phase: .checking, currentVersion: "0.8.9", progress: 1, actions: [
                UpdateWindowAction(title: "Cancel This Update Check and Return to Reading", key: "c") {}
            ]))
            #expect(root.bounds.width > compactWidth && root.bounds.width <= 560)
            let views = descendants(of: root)
            for button in views.compactMap({ $0 as? NSButton }) {
                #expect(root.bounds.contains(root.convert(button.bounds, from: button)))
            }
            for label in views.compactMap({ $0 as? NSTextField }).filter({ !$0.isHidden && !$0.stringValue.isEmpty }) {
                #expect(label.frame.width >= label.intrinsicContentSize.width)
            }
            let fill = try #require(views.first { $0.layer?.backgroundColor == TokyoNight.blue.cgColor })
            #expect(abs(fill.bounds.width - root.bounds.width + 48) < 0.5)
            controller.update(UpdateWindowContent(phase: .checking, currentVersion: "0.8.9"))
            let compactAnimation = try #require(fill.layer?.animation(forKey: "preparing") as? CABasicAnimation)
            #expect((compactAnimation.toValue as? NSNumber)?.doubleValue == Double(root.bounds.width - 48))
            controller.update(UpdateWindowContent(phase: .checking, currentVersion: "0.8.9", releaseNotes: longNotes()))
            let expandedAnimation = try #require(fill.layer?.animation(forKey: "preparing") as? CABasicAnimation)
            #expect((expandedAnimation.toValue as? NSNumber)?.doubleValue == 512)
            controller.update(UpdateWindowContent(phase: .upToDate, currentVersion: "0.8.9"))
            #expect(root.bounds.width == compactWidth)
        }
    }

    @Test
    func closingNotifiesOnceAndDismissDoesNotNotify() throws {
        let controller = makeController()
        var closes = 0
        controller.onClose = { closes += 1 }
        let window = try #require(controller.window)
        controller.dismiss()
        #expect(closes == 0)
        controller.present(UpdateWindowContent(phase: .checking, currentVersion: "0.8.7"), activate: false)
        send("\u{1b}", keyCode: 53, to: window)
        send("\u{1b}", keyCode: 53, repeating: true, to: window)
        window.close()
        #expect(closes == 1)
        controller.present(UpdateWindowContent(phase: .upToDate, currentVersion: "0.8.7"), activate: false)
        window.close()
        #expect(closes == 2)
    }

    @Test
    func closeCallbackCanPresentTheNextState() throws {
        let controller = makeController()
        defer { controller.onClose = nil; controller.dismiss() }
        var closes = 0
        controller.onClose = {
            closes += 1
            controller.present(UpdateWindowContent(phase: .error, currentVersion: "0.8.7", message: "Try again."), activate: false)
        }
        let window = try #require(controller.window)
        window.performClose(nil)
        #expect(closes == 1)
        #expect(window.isVisible)
    }

    @Test
    func everyPhaseKeepsFixedWidthAndWrapsLongReleaseNotes() throws {
        _ = NSApplication.shared
        let preference = AppPreferenceKeys.appLanguage
        let previous = UserDefaults.standard.object(forKey: preference)
        defer { UserDefaults.standard.set(previous, forKey: preference) }
        let phases: [UpdateWindowContent.Phase] = [.checking, .upToDate, .available, .downloading, .extracting, .ready, .installing, .error]
        for language in AppUILanguage.allCases {
            UserDefaults.standard.set(language.rawValue, forKey: preference)
            let controller = UpdateWindowController()
            defer { controller.dismiss() }
            for style in [NSScroller.Style.legacy, .overlay] {
                for phase in phases {
                    controller.update(UpdateWindowContent(
                        phase: phase, currentVersion: "0.8.7", updateVersion: "0.8.8",
                        releaseNotes: [AppReleaseNotesSection(version: "0.8.8", notes: [
                            String(repeating: "LongReleaseNoteWithoutSpaces", count: 100),
                            String(repeating: "修复恢复阅读位置后的页面布局，并改进更新说明。", count: 100),
                            String(repeating: "Updated.\n", count: 100)
                        ])],
                        message: String(repeating: "Long status message. ", count: 100),
                        actions: [
                            UpdateWindowAction(title: language.text(.later), key: "l") {},
                            UpdateWindowAction(title: language.text(.openGitHub), key: "o") {},
                            UpdateWindowAction(title: language.text(.restartAndUpdate), key: "r", isPrimary: true) {}
                        ]
                    ))
                    let root = try #require(controller.window?.contentView)
                    let views = descendants(of: root)
                    let scroll = try #require(views.compactMap { $0 as? NSScrollView }.first)
                    scroll.scrollerStyle = style
                    root.layoutSubtreeIfNeeded()
                    scroll.tile()
                    let text = try #require(scroll.documentView as? NSTextView)
                    text.layoutManager?.ensureLayout(for: text.textContainer!)
                    #expect(abs(root.bounds.width - 560) < 0.5)
                    #expect(abs(root.fittingSize.width - 560) < 0.5)
                    #expect(abs(text.bounds.width - scroll.contentView.bounds.width) < 0.5)
                    #expect(text.bounds.height > scroll.contentView.bounds.height)
                    #expect(!scroll.hasHorizontalScroller)
                    #expect(text.isSelectable && !text.isEditable)
                    #expect(!root.mouseDownCanMoveWindow)
                    for button in views.compactMap({ $0 as? NSButton }) {
                        #expect(root.bounds.contains(root.convert(button.bounds, from: button)))
                    }
                }
            }
        }
    }

    @Test
    func notesStopAtTheFinalTextLineWithoutAVisibleScroller() throws {
        _ = NSApplication.shared
        let controller = UpdateWindowController()
        defer { controller.dismiss() }
        for count in [25, 1] {
            let notes = (0..<count).map { "Change \($0): " + String(repeating: "Improve reading and document navigation across different layouts. ", count: 3) }
            controller.update(UpdateWindowContent(phase: .ready, currentVersion: "0.8.7", updateVersion: "0.8.8",
                releaseNotes: [AppReleaseNotesSection(version: "0.8.8", notes: notes)]))
            let window = try #require(controller.window)
            let scroll = try #require(descendants(of: window.contentView!).compactMap { $0 as? NSScrollView }.first)
            let text = try #require(scroll.documentView as? NSTextView)
            let layout = try #require(text.layoutManager)
            let container = try #require(text.textContainer)
            layout.ensureLayout(for: container)
            let lastCharacter = text.string.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count - 1
            let glyph = layout.glyphIndexForCharacter(at: lastCharacter)
            let bottom = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).maxY + text.textContainerOrigin.y
            send("G", modifiers: .shift, to: window)
            #expect(!scroll.hasVerticalScroller)
            #expect(text.bounds.height <= max(scroll.contentView.bounds.height, bottom + text.textContainerInset.height + 1))
            if bottom > scroll.contentView.bounds.height {
                #expect(abs(scroll.contentView.bounds.maxY - bottom) <= text.textContainerInset.height + 1)
            } else {
                #expect(scroll.contentView.bounds.minY == 0)
            }
        }
    }

    private func makeController(actions: [UpdateWindowAction] = []) -> UpdateWindowController {
        _ = NSApplication.shared
        let controller = UpdateWindowController()
        controller.present(UpdateWindowContent(phase: .ready, currentVersion: "0.8.7", updateVersion: "0.8.8", releaseNotes: longNotes(), actions: actions), activate: false)
        return controller
    }

    private func longNotes() -> [AppReleaseNotesSection] {
        [AppReleaseNotesSection(version: "0.8.8", notes: (0..<80).map { "Change \($0): improve reading, navigation, and document handling." })]
    }

    private func send(_ characters: String, keyCode: UInt16 = 0, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false, to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: repeating, keyCode: keyCode)!
        window.sendEvent(event)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

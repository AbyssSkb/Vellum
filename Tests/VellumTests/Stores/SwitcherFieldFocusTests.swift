@preconcurrency import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Switcher field focus")
struct SwitcherFieldFocusTests {
    @Test(arguments: [false, true])
    func updatingASwitcherDoesNotReclaimAnotherResponder(history: Bool) async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
        appState.isTabSwitcherPresented = !history
        appState.isAIConversationHistoryPresented = history
        let content = history ? AnyView(AIConversationHistorySwitcherOverlay()) : AnyView(TabSwitcherOverlay())
        let host = NSHostingView(rootView: AnyView(content.environmentObject(appState)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            appState.keyboardController.cancelInput()
            host.rootView = AnyView(EmptyView())
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        func fields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        let field = try #require(fields(in: host).first { $0.isEditable })
        field.stringValue = "🧭e\u{301}标题"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await waitForTestCondition("The switcher field did not receive initial focus") {
            field.currentEditor().map { window.firstResponder === $0 } == true
        }
        let editor = try #require(field.currentEditor())
        let receivedInitialFocus = window.firstResponder === editor
        #expect(receivedInitialFocus)
        #expect(editor.selectedRange == NSRange(location: field.stringValue.utf16.count, length: 0))
        let markedEditor = try #require(editor as? NSTextView)
        markedEditor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            #expect(field.delegate?.control?(field, textView: markedEditor, doCommandBy: selector) == false)
            let preservedCompositionFocus = window.firstResponder === markedEditor
            #expect(preservedCompositionFocus)
        }
        markedEditor.unmarkText()

        let otherEditor = NSTextView(frame: .zero)
        host.addSubview(otherEditor)
        #expect(window.makeFirstResponder(otherEditor))
        field.stringValue += " changed"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        host.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()
        await nextTestMainQueueTurn()
        let preservedNewResponder = window.firstResponder === otherEditor
        #expect(preservedNewResponder)
    }
}

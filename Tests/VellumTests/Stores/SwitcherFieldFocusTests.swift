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
        let suite = "Vellum.SwitcherFieldFocus.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appState = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false,
            notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
        ))
        appState.isTabSwitcherPresented = !history
        appState.isAIConversationHistoryPresented = history
        let content = history ? AnyView(AIConversationHistorySwitcherOverlay()) : AnyView(TabSwitcherOverlay())
        let host = NSHostingView(rootView: content.environmentObject(appState))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func fields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        let field = try #require(fields(in: host).first { $0.isEditable })
        field.stringValue = "🧭e\u{301}标题"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await Task.sleep(for: .milliseconds(80))
        let editor = try #require(field.currentEditor())
        let receivedInitialFocus = window.firstResponder === editor
        #expect(receivedInitialFocus)
        #expect(editor.selectedRange == NSRange(location: field.stringValue.utf16.count, length: 0))
        if let markedEditor = editor as? NSTextView {
            markedEditor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
                #expect(field.delegate?.control?(field, textView: markedEditor, doCommandBy: selector) == false)
                let preservedCompositionFocus = window.firstResponder === markedEditor
                #expect(preservedCompositionFocus)
            }
            markedEditor.unmarkText()
        }

        let otherEditor = NSTextView(frame: .zero)
        host.addSubview(otherEditor)
        #expect(window.makeFirstResponder(otherEditor))
        field.stringValue += " changed"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await Task.sleep(for: .milliseconds(80))
        let preservedNewResponder = window.firstResponder === otherEditor
        #expect(preservedNewResponder)
    }
}

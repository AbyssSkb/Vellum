import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary editing focus", .serialized)
@MainActor
struct DictionaryEditingFocusTests {
    @Test(arguments: ["input", "textarea", "editable"])
    func editingReceivesVimLettersAndSpaces(_ field: String) async throws {
        try await withPopover { view, window, barrier in
            try await focus(field, in: view, barrier: barrier)
            for key in ["k", "i", "n", "d", " ", "p"] {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    let event = try keyEvent(key, type: type, in: window)
                    let handled = view.handleKeyEvent(event)
                    #expect(!handled)
                    if !handled {
                        if type == .keyDown { window.firstResponder?.keyDown(with: event) }
                        else { window.firstResponder?.keyUp(with: event) }
                    }
                }
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var value: String?
            repeat {
                let text = try await view.webView.evaluateJavaScript("document.getElementById('\(field)').value ?? document.getElementById('\(field)').textContent") as? String
                value = text?.replacingOccurrences(of: "\u{00a0}", with: " ")
                if value == "kind p" { break }
                await nextTestMainQueueTurn()
            } while ContinuousClock.now < deadline
            #expect(value == "kind p")
        }
    }

    @Test
    func leavingEditingRestoresVimAndEscapeStillDismisses() async throws {
        try await withPopover { view, window, barrier in
            #expect(try view.handleKeyEvent(keyEvent("j", in: window)))
            try await focus("input", in: view, barrier: barrier)
            #expect(try !view.handleKeyEvent(keyEvent("j", type: .keyUp, in: window)))
            #expect(try !view.handleKeyEvent(keyEvent("g", in: window)))
            try await focus("body", in: view, barrier: barrier)
            #expect(try view.handleKeyEvent(keyEvent("j", in: window)))
            #expect(try view.handleKeyEvent(keyEvent("j", type: .keyUp, in: window)))
            try await focus("editable", in: view, barrier: barrier)
            var dismissed = false
            view.onDismiss = { dismissed = true }
            #expect(try view.handleKeyEvent(keyEvent("\u{1b}", in: window)))
            #expect(dismissed)
        }
    }

    @Test
    func stoppedPagesCannotRestoreTheirEditingFocus() async throws {
        try await withPopover { view, window, barrier in
            try await focus("input", in: view, barrier: barrier)
            view.stop()
            #expect(try view.handleKeyEvent(keyEvent("j", in: window)))
            #expect(try view.handleKeyEvent(keyEvent("j", type: .keyUp, in: window)))
            try await focus("body", in: view, barrier: barrier)
            try await focus("editable", in: view, barrier: barrier)
            #expect(try view.handleKeyEvent(keyEvent("j", in: window)))
        }
    }

    private func focus(_ field: String, in view: DictionaryPopoverView, barrier: DictionaryEditingBarrier) async throws {
        let previous = barrier.count
        _ = try await view.webView.evaluateJavaScript("document.getElementById('\(field)').focus();window.webkit.messageHandlers.dictionaryEditingTest.postMessage(null);null;", in: nil, contentWorld: .defaultClient)
        try await waitForTestCondition("Editable focus reaches the native event bridge", dispatchAppKitEvents: true) { barrier.count > previous }
    }

    private func keyEvent(_ key: String, type: NSEvent.EventType = .keyDown, in window: NSWindow) throws -> NSEvent {
        let codes: [String: UInt16] = ["k": 40, "i": 34, "n": 45, "d": 2, " ": 49, "p": 35, "g": 5, "j": 38, "\u{1b}": 53]
        return try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, characters: key,
                                            charactersIgnoringModifiers: key, isARepeat: false, keyCode: codes[key] ?? 0))
    }

    private func withPopover(_ body: @MainActor (DictionaryPopoverView, NSWindow, DictionaryEditingBarrier) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumEditing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mdx = directory.appendingPathComponent("fixture.mdx")
        let html = "<input id='input'><textarea id='textarea'></textarea><div id='editable' contenteditable='true'></div><div id='body' tabindex='0' style='height:3000px'>Dictionary body</div>"
        try MDictFixture(entries: [("word", Data(html.utf8))]).data.write(to: mdx)
        let defaults = UserDefaults.standard
        let keys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(mdx.path, forKey: keys[0])
        defaults.set(false, forKey: keys[1])
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let view = DictionaryPopoverView()
        let barrier = DictionaryEditingBarrier()
        view.webView.configuration.userContentController.add(barrier, contentWorld: .defaultClient, name: "dictionaryEditingTest")
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.contentView = nil; window.close() }
        view.lookup("word")
        try await waitForTestCondition("Dictionary editing fixture is ready", dispatchAppKitEvents: true) { !view.isLoading }
        window.makeFirstResponder(view.webView)
        try await body(view, window, barrier)
    }
}

@MainActor
private final class DictionaryEditingBarrier: NSObject, WKScriptMessageHandler {
    var count = 0
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { count += 1 }
}

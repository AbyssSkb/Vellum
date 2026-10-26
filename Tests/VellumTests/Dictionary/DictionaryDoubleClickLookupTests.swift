import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary double-click lookup", .serialized)
@MainActor
struct DictionaryDoubleClickLookupTests {
    @Test
    func selectedDefinitionWordsOpenInTheSamePopoverAndCanBeLookedUpAgain() async throws {
        try await withPopover { view in
            #expect(try await headword(in: view) == "source")
            for word in ["target", "source"] {
                var started = false
                view.onLoadingChange = { if $0 { started = true } }
                let selected = try await doubleClick("lookup", in: view)
                #expect(selected == word)
                try await waitForTestCondition("Double-clicked definition word starts lookup from the completed source page", dispatchAppKitEvents: true) { started }
                try await waitForTestCondition("Double-clicked dictionary entry is presented", dispatchAppKitEvents: true) { !view.isLoading }
                #expect(try await headword(in: view) == word)
            }
        }
    }

    @Test
    func emptySelectionsAndInteractiveControlsDoNotStartAnotherLookup() async throws {
        try await withPopover { view in
            let originalURL = view.webView.url
            var started = false
            view.onLoadingChange = { if $0 { started = true } }
            _ = try await doubleClick("lookup", selectingText: false, in: view)
            try await drainPageEvents(in: view)
            #expect(!started)
            #expect(try await doubleClick("headword", selectedID: "lookup", in: view) == "target")
            try await drainPageEvents(in: view)
            #expect(!started)
            for id in ["button-word", "link-word", "editable-word"] {
                #expect(try await doubleClick(id, in: view) == "target")
                try await drainPageEvents(in: view)
                #expect(!started)
            }
            #expect(view.webView.url == originalURL)
            #expect(try await headword(in: view) == "source")
        }
    }

    @Test
    func dismissedPagesCannotLookUpDoubleClickedWords() async throws {
        try await withPopover { view in
            let originalURL = view.webView.url
            view.dismiss()
            var started = false
            view.onLoadingChange = { if $0 { started = true } }
            #expect(try await doubleClick("lookup", in: view) == "target")
            try await drainPageEvents(in: view)
            #expect(!started)
            #expect(view.webView.url == originalURL)
            #expect(try await headword(in: view) == "source")
        }
    }

    private func headword(in view: DictionaryPopoverView) async throws -> String? {
        try await view.webView.evaluateJavaScript("document.querySelector('h1').textContent") as? String
    }

    private func doubleClick(_ id: String, selectingText: Bool = true, selectedID: String? = nil, in view: DictionaryPopoverView) async throws -> String? {
        try await view.webView.evaluateJavaScript("""
            (() => {
              const element = document.getElementById('\(id)');
              const selection = window.getSelection();
              selection.removeAllRanges();
              if (\(selectingText ? "true" : "false")) {
                const range = document.createRange();
                range.selectNodeContents(document.getElementById('\(selectedID ?? id)'));
                selection.addRange(range);
              }
              const text = selection.toString();
              const rect = element.getBoundingClientRect();
              element.dispatchEvent(new MouseEvent('dblclick', {bubbles: true, cancelable: true, detail: 2,
                clientX: rect.x + rect.width / 2, clientY: rect.y + rect.height / 2}));
              return text;
            })();
            """) as? String
    }

    private func drainPageEvents(in view: DictionaryPopoverView) async throws {
        var finished = false
        var error: Error?
        view.webView.callAsyncJavaScript("""
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            return true;
            """, in: nil, in: .page) { result in
                if case let .failure(failure) = result { error = failure }
                finished = true
            }
        try await waitForTestCondition("Double-click page events finish", dispatchAppKitEvents: true) { finished }
        if let error { throw error }
        await nextTestMainQueueTurn()
    }

    private func withPopover(_ body: @MainActor (DictionaryPopoverView) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumDoubleClick-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "<h1 id='headword'>source</h1><p>Definition: <span id='lookup'>target</span></p><button><span id='button-word'>target</span></button><a href='entry://source'><span id='link-word'>target</span></a><div contenteditable='true'><span id='editable-word'>target</span></div>"
        let target = "<h1>target</h1><p>Definition: <span id='lookup'>source</span></p>"
        let mdx = directory.appendingPathComponent("fixture.mdx")
        try MDictFixture(entries: [("source", Data(source.utf8)), ("target", Data(target.utf8))]).data.write(to: mdx)
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
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.contentView = nil; window.close() }
        view.lookup("source")
        try await waitForTestCondition("The initial dictionary page is fully presented", dispatchAppKitEvents: true) { !view.isLoading }
        #expect(try await headword(in: view) == "source")
        try await body(view)
    }
}

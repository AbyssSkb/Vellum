import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Oxford dictionary scrolling", .serialized)
@MainActor
struct DictionaryOxfordScrollTests {
    @Test(.timeLimit(.minutes(1)))
    func actualDocumentEntryScrollsThroughScriptAndNativeKeys() async throws {
        guard let path = ProcessInfo.processInfo.environment["VELLUM_TEST_MDX_PATH"] else { return }
        let defaults = UserDefaults.standard
        let keys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(path, forKey: AppPreferenceKeys.dictionaryPath)
        defaults.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        let view = DictionaryPopoverView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.contentView = nil; window.close() }
        view.lookup("document")
        try await waitForTestCondition("The actual Oxford document entry is presented", timeout: .seconds(20), dispatchAppKitEvents: true) { !view.isLoading }
        let webView = view.webView
        #expect(try await webView.evaluateJavaScript("document.querySelector('.headword')?.textContent") as? String == "document")
        #expect(try await webView.evaluateJavaScript("document.scrollingElement.scrollHeight > window.innerHeight") as? Bool == true)
        #expect(try await webView.evaluateJavaScript("typeof window.vellumDictionaryScroll?.by", in: nil, contentWorld: .defaultClient) as? String == "function")
        _ = try await webView.evaluateJavaScript("""
            window.dictionaryTestTime = 1000;
            performance.now = () => window.dictionaryTestTime;
            window.requestAnimationFrame = callback => { window.dictionaryTestFrame = callback; return 1; };
            window.cancelAnimationFrame = () => { window.dictionaryTestFrame = null; };
            null;
            """, in: nil, contentWorld: .defaultClient)
        func advance(_ frames: Int) async throws -> Double {
            _ = try await webView.evaluateJavaScript("""
                for (let i=0;i<\(frames);i++) {
                  window.dictionaryTestTime += 1000/60;
                  const callback=window.dictionaryTestFrame;
                  window.dictionaryTestFrame=null;
                  callback?.(window.dictionaryTestTime);
                }
                null;
                """, in: nil, contentWorld: .defaultClient)
            return try #require(try await webView.evaluateJavaScript("window.scrollY") as? Double)
        }
        func send(_ key: String, type: NSEvent.EventType = .keyDown) throws {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, characters: key,
                                                    charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "j" ? 38 : 2))
            #expect(view.handleKeyEvent(event))
        }
        _ = try await webView.evaluateJavaScript("window.vellumDictionaryScroll.by(0,200);null;", in: nil, contentWorld: .defaultClient)
        let scripted = try await advance(60)
        #expect(scripted >= 199)
        _ = try await webView.evaluateJavaScript("window.vellumDictionaryScroll.edge(false);null;", in: nil, contentWorld: .defaultClient)
        #expect(try await advance(60) == 0)
        try send("d")
        try send("d", type: .keyUp)
        let halfPage = try await advance(60)
        #expect(halfPage > 100)
        try send("j")
        let held = try await advance(30)
        try send("j", type: .keyUp)
        #expect(held > halfPage + 300)
    }
}

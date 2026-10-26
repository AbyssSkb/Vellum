import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary scrolling while loading", .serialized)
@MainActor
struct DictionaryLoadingScrollTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func heldScrollDuringLookupStartsWhenPresentedUnlessReleased(releasedWhileLoading: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumLoadingScroll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mdx = directory.appendingPathComponent("fixture.mdx")
        try MDictFixture(entries: [("long", Data("<div style='height:6000px'>Long definition</div>".utf8))]).data.write(to: mdx)
        let defaults = UserDefaults.standard
        let keys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(mdx.path, forKey: keys[0])
        defaults.set(false, forKey: keys[1])
        let view = DictionaryPopoverView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        view.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 560)
        view.webView.configuration.userContentController.addUserScript(WKUserScript(source: """
            window.dictionaryTestTime = 1000;
            performance.now = () => window.dictionaryTestTime;
            window.requestAnimationFrame = callback => { window.dictionaryTestFrame = callback; return 1; };
            window.cancelAnimationFrame = () => { window.dictionaryTestFrame = null; };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        defer { view.stop() }
        func send(_ type: NSEvent.EventType) throws {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, characters: "j",
                                                    charactersIgnoringModifiers: "j", isARepeat: false, keyCode: 38))
            #expect(view.handleKeyEvent(event))
        }
        view.lookup("long")
        #expect(view.isLoading)
        try send(.keyDown)
        if releasedWhileLoading { try send(.keyUp) }
        try await waitForTestCondition("Dictionary content is ready after the scroll key was pressed", timeout: .seconds(20)) { !view.isLoading }
        _ = try await view.webView.evaluateJavaScript("""
            for (let i=0;i<30;i++) {
              window.dictionaryTestTime += 1000/60;
              const callback=window.dictionaryTestFrame;
              window.dictionaryTestFrame=null;
              callback?.(window.dictionaryTestTime);
            }
            null;
            """, in: nil, contentWorld: .defaultClient)
        let position = try #require(try await view.webView.evaluateJavaScript("window.scrollY") as? Double)
        if releasedWhileLoading {
            #expect(position == 0)
        } else {
            #expect(position > 300)
            try send(.keyUp)
        }
    }
}

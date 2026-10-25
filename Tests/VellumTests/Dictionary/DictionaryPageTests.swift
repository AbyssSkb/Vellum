import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary pages", .serialized)
@MainActor
struct DictionaryPageTests {
    @Test
    func routesDictionaryLinksWithoutLosingEncodedNamesAndAudioHashes() throws {
        let entry = try #require(DictionaryPage.link("entry://caf%C3%A9%20au%20lait#caf%C3%A9_1"))
        #expect(entry.kind == "entry")
        #expect(entry.value == "café au lait")
        #expect(entry.anchor == "café_1")
        let audio = try #require(DictionaryPage.link("sound://_hello%23_uss_1.mp3"))
        #expect(audio.value == "_hello%23_uss_1.mp3")
        #expect(DictionaryPage.link("sound://_hello#_uss_1.mp3")?.value == "_hello#_uss_1.mp3")
        #expect(DictionaryPage.link("sound://100%2525.mp3")?.value == "100%2525.mp3")
        #expect(DictionaryPage.link("entry://@wordlists_oxford_dataset=english&list=ox3000")?.value == "@wordlists_oxford_dataset=english&list=ox3000")
        #expect(DictionaryPage.link("https://example.com") == nil)
        #expect(DictionaryPage.link("file:///etc/passwd") == nil)
        #expect(DictionaryPage.resourcePath(URL(string: "vellum-dictionary://dictionary/images/a%23b.png")!) == "/images/a%23b.png")
        #expect(DictionaryPage.resourcePath(URL(string: "vellum-dictionary://other/a.png")!) == nil)
        let id = UUID()
        #expect(DictionaryPage.isEntryURL(URL(string: DictionaryPage.entryURL(id: id).absoluteString + "#hello"), id: id))
        #expect(!DictionaryPage.isEntryURL(DictionaryPage.entryURL(id: UUID()), id: id))
    }

    @Test
    func anUnconfiguredDictionaryDoesNotStartLoadingOrPlayback() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppPreferenceKeys.dictionaryPath)
        defaults.removeObject(forKey: AppPreferenceKeys.dictionaryPath)
        defer {
            if let previous { defaults.set(previous, forKey: AppPreferenceKeys.dictionaryPath) }
        }
        let view = DictionaryPopoverView()
        defer { view.stop() }
        view.lookup("hello")
        #expect(!view.isLoading)
        #expect(view.webView.url == nil)
        #expect(view.player == nil)
    }

    @Test
    func escapeDismissesOnKeyDownAndConsumesKeyRelease() throws {
        let view = DictionaryPopoverView()
        defer { view.stop() }
        var dismissals = 0
        view.onDismiss = { dismissals += 1 }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, characters: "\u{1b}",
                                                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            #expect(view.handleKeyEvent(event))
        }
        #expect(dismissals == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func configuredOxfordLookupFinishesInTheHostedPopover() async throws {
        guard let path = ProcessInfo.processInfo.environment["VELLUM_TEST_MDX_PATH"] else { return }
        let mdx = URL(fileURLWithPath: path)
        let defaults = UserDefaults.standard
        let keys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
        defaults.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        let view = DictionaryPopoverView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.close() }
        view.lookup("Experts")
        do {
            try await waitForTestCondition("Hosted dictionary lookup leaves its loading state", timeout: .seconds(20)) { !view.isLoading }
        } catch {
            let readyState = try? await view.webView.evaluateJavaScript("document.readyState")
            let word = try? await view.webView.evaluateJavaScript("document.querySelector('.headword')?.textContent")
            Issue.record("Hosted lookup stuck: URL=\(String(describing: view.webView.url)), WebKit loading=\(view.webView.isLoading), readyState=\(String(describing: readyState)), word=\(String(describing: word))")
            throw error
        }
        let headword = try #require(try await view.webView.evaluateJavaScript("document.querySelector('.headword')?.textContent") as? String)
        #expect(headword.lowercased().contains("expert"))
    }

    @Test(.timeLimit(.minutes(1)))
    func heldScrollingStartsWithoutKeyRepeatAndStaysSmoothAtReaderSpeed() async throws {
        let view = DictionaryPopoverView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.close() }
        let probe = DictionaryPageProbe()
        view.webView.navigationDelegate = probe
        view.webView.loadHTMLString(DictionaryPage.document("<div style='width:3000px;height:6000px'>Scroll fixture</div>"), baseURL: nil)
        try await waitForTestCondition("Scroll fixture loaded") { probe.finished }
        try await installScrollClock(in: view.webView)
        func send(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = [], repeated: Bool = false) throws {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, characters: "j",
                                                    charactersIgnoringModifiers: "j", isARepeat: repeated, keyCode: 38))
            #expect(view.handleKeyEvent(event))
        }
        func advance(_ frames: Int) async throws -> Double {
            try await advanceScrollClock(frames, in: view.webView)[1]
        }
        try send(.keyDown)
        let firstFrame = try await advance(1)
        #expect(firstFrame > 0 && firstFrame < 72)
        let early = try await advance(5)
        #expect(early > firstFrame)
        try send(.keyDown, repeated: true)
        let middle = try await advance(12)
        let later = try await advance(6)
        let steady = try await advance(6)
        #expect(middle > early)
        #expect(abs(later - middle - 672 * 0.1) <= 2)
        #expect(abs((steady - later) - (later - middle)) <= 2)
        try send(.keyUp, modifiers: .command)
        let stopped = try await advance(60)
        #expect(try await advance(12) == stopped)
        try send(.keyDown)
        _ = try await advance(6)
        view.stop()
        let cancelled = try await advance(1)
        #expect(try await advance(12) == cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func vimKeysScrollTheDictionaryAndKeepKeyReleasesAndCommandsSeparate() async throws {
        let view = DictionaryPopoverView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.close() }
        let probe = DictionaryPageProbe()
        view.webView.navigationDelegate = probe
        view.webView.loadHTMLString(DictionaryPage.document("<div style='width:3000px;height:6000px'>Dictionary navigation</div>"), baseURL: nil)
        try await waitForTestCondition("Dictionary scroll fixture loaded") { probe.finished }
        try await installScrollClock(in: view.webView)
        let height = try #require(try await view.webView.evaluateJavaScript("window.innerHeight") as? Double)

        func send(_ key: String, type: NSEvent.EventType = .keyDown, repeat repeated: Bool = false, modifiers: NSEvent.ModifierFlags = []) throws -> Bool {
            let keyCodes: [String: UInt16] = ["j": 38, "k": 40, "h": 4, "l": 37, "d": 2, "u": 32, "f": 3, "b": 11, " ": 49, "g": 5, "G": 5]
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, characters: key,
                                                    charactersIgnoringModifiers: key, isARepeat: repeated, keyCode: keyCodes[key] ?? 0))
            return view.handleKeyEvent(event)
        }
        func settle() async throws -> [Double] {
            try await advanceScrollClock(60, in: view.webView)
        }
        func tap(_ key: String) async throws -> [Double] {
            #expect(try send(key))
            #expect(try send(key, type: .keyUp))
            return try await settle()
        }
        #expect(try await tap("j") == [0, 72])
        #expect(try send("j"))
        #expect(try send("j", repeat: true))
        #expect(try send("j", type: .keyUp))
        #expect(try await settle() == [0, 144])
        #expect(try await tap("k") == [0, 72])
        #expect(try await tap("l") == [72, 72])
        #expect(try await tap("h") == [0, 72])
        #expect(abs(try await tap("d")[1] - 72 - height / 2) <= 1)
        #expect(abs(try await tap("u")[1] - 72) <= 1)
        #expect(abs(try await tap("f")[1] - 72 - height) <= 1)
        #expect(abs(try await tap("b")[1] - 72) <= 1)
        #expect(abs(try await tap(" ")[1] - 72 - height) <= 1)
        #expect(try send("g"))
        #expect(try send("g", repeat: true))
        #expect(try send("g", type: .keyUp))
        #expect(abs(try await settle()[1] - 72 - height) <= 1)
        #expect(try await tap("g")[1] == 0)
        let bottom = try await tap("G")[1]
        #expect(bottom > height * 3)
        #expect(try send("g"))
        #expect(try await tap("j")[1] == bottom)
        #expect(try await tap("g")[1] == bottom)
        view.stop()
        #expect(try await tap("g")[1] == bottom)
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            #expect(try !send("f", modifiers: modifier))
            #expect(try await settle()[1] == bottom)
        }
    }

    private func installScrollClock(in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript("""
            window.dictionaryTestTime = 1000;
            performance.now = () => window.dictionaryTestTime;
            window.requestAnimationFrame = callback => { window.dictionaryTestFrame = callback; return 1; };
            window.cancelAnimationFrame = () => { window.dictionaryTestFrame = null; };
            null;
            """, in: nil, contentWorld: .defaultClient)
    }

    private func advanceScrollClock(_ frames: Int, in webView: WKWebView) async throws -> [Double] {
        _ = try await webView.evaluateJavaScript("""
            for (let i = 0; i < \(frames); i++) {
              window.dictionaryTestTime += 1000 / 60;
              const callback = window.dictionaryTestFrame;
              window.dictionaryTestFrame = null;
              callback?.(window.dictionaryTestTime);
            }
            null;
            """, in: nil, contentWorld: .defaultClient)
        return try #require(try await webView.evaluateJavaScript("[window.scrollX,window.scrollY]") as? [Double])
    }

    @Test(.timeLimit(.minutes(1)))
    func customOriginRunsDictionaryScriptsAndStorageButBlocksRemoteRequests() async throws {
        let handler = DictionaryResourceHandler()
        let url = DictionaryPage.entryURL(id: UUID())
        handler.setDocument("""
            <div class="examples"><a class="sound pron-us app" href="sound://example.mp3">example</a></div>
            <div class="phonetics"><a class="sound pron-uk" href="sound://hello__gb.mp3">UK</a>
            <a class="sound pron-us" href="sound://hello__us.mp3">US</a></div>
            <script>localStorage.setItem('vellum-dictionary-test', 'works'); window.dictionaryScriptRan = true;</script>
            """, at: url, location: URL(fileURLWithPath: "/"))
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: DictionaryPage.scheme)
        configuration.userContentController.addUserScript(WKUserScript(source: DictionaryPage.linkCaptureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        let probe = DictionaryPageProbe()
        configuration.userContentController.add(probe, contentWorld: .defaultClient, name: "dictionary")
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 500), configuration: configuration)
        webView.navigationDelegate = probe
        defer {
            webView.stopLoading()
            handler.stop()
            configuration.userContentController.removeAllScriptMessageHandlers()
        }
        webView.load(URLRequest(url: url))
        try await waitForTestCondition("Dictionary custom-scheme page loaded") { probe.finished || probe.error != nil }
        if let error = probe.error { throw error }
        #expect(try await webView.evaluateJavaScript("window.dictionaryScriptRan") as? Bool == true)
        #expect(try await webView.evaluateJavaScript("localStorage.getItem('vellum-dictionary-test')") as? String == "works")
        let pronunciations = try #require(try await webView.evaluateJavaScript(DictionaryPage.pronunciationScript) as? [String: String])
        #expect(pronunciations == ["american": "sound://hello__us.mp3", "british": "sound://hello__gb.mp3"])
        _ = try await webView.evaluateJavaScript("document.querySelector('.phonetics .pron-us').click();null;")
        try await waitForTestCondition("Dictionary sound link reached isolated native bridge") { !probe.links.isEmpty }
        #expect(probe.links == ["sound://hello__us.mp3"])
        let blocked = try await webView.callAsyncJavaScript("""
            return await new Promise(resolve => {
              document.addEventListener('securitypolicyviolation', event => resolve(event.violatedDirective), {once:true});
              fetch('https://example.invalid/dictionary-test').catch(() => {});
              setTimeout(() => resolve('timeout'), 1000);
            });
            """, arguments: [:], in: nil, contentWorld: .page)
        #expect(blocked as? String == "connect-src")
    }
}

@MainActor
private final class DictionaryPageProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var finished = false
    var error: Error?
    var links: [String] = []

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.error = error }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let link = message.body as? String { links.append(link) }
    }
}

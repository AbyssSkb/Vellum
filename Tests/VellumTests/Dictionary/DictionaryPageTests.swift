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
        let height = try #require(try await view.webView.evaluateJavaScript("window.innerHeight") as? Double)

        func send(_ key: String, type: NSEvent.EventType = .keyDown, repeat repeated: Bool = false, modifiers: NSEvent.ModifierFlags = []) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, characters: key,
                                                    charactersIgnoringModifiers: key, isARepeat: repeated, keyCode: 0))
            return view.handleKeyEvent(event)
        }
        func position() async throws -> [Double] {
            try #require(try await view.webView.evaluateJavaScript("[window.scrollX,window.scrollY]") as? [Double])
        }
        #expect(try send("j"))
        #expect(try await position() == [0, 72])
        #expect(try send("j", type: .keyUp))
        #expect(try await position() == [0, 72])
        #expect(try send("j", repeat: true))
        #expect(try await position() == [0, 144])
        #expect(try send("k"))
        #expect(try send("l"))
        #expect(try await position() == [72, 72])
        #expect(try send("h"))
        #expect(try await position() == [0, 72])
        #expect(try send("d"))
        #expect(abs(try await position()[1] - 72 - height / 2) <= 1)
        #expect(try send("u"))
        #expect(abs(try await position()[1] - 72) <= 1)
        #expect(try send("f"))
        #expect(abs(try await position()[1] - 72 - height) <= 1)
        #expect(try send("b"))
        #expect(abs(try await position()[1] - 72) <= 1)
        #expect(try send(" "))
        #expect(abs(try await position()[1] - 72 - height) <= 1)
        #expect(try send("g"))
        #expect(try send("g", repeat: true))
        #expect(abs(try await position()[1] - 72 - height) <= 1)
        #expect(try send("g"))
        #expect(try await position()[1] == 0)
        #expect(try send("G"))
        let bottom = try await position()[1]
        #expect(bottom > height * 3)
        #expect(try send("g"))
        #expect(try send("j"))
        #expect(try send("g"))
        #expect(try await position()[1] == bottom)
        view.stop()
        #expect(try send("g"))
        #expect(try await position()[1] == bottom)
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            #expect(try !send("f", modifiers: modifier))
            #expect(try await position()[1] == bottom)
        }
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

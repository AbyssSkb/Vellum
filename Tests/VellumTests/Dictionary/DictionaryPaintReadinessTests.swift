import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary paint readiness", .serialized)
@MainActor
struct DictionaryPaintReadinessTests {
    @Test(.timeLimit(.minutes(1)))
    func explicitlyConfiguredDictionaryKeepsItsInitialNavigationColors() async throws {
        guard let path = ProcessInfo.processInfo.environment["VELLUM_TEST_MDX_PATH"], !path.isEmpty else { return }
        let defaults = UserDefaults.standard
        let keys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(path, forKey: keys[0])
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
        var samples: [[String: Any]]?
        var error: Error?
        view.onLoadingChange = { [weak view] loading in
            guard !loading, samples == nil, let view else { return }
            view.webView.callAsyncJavaScript(#"""
                const nav = document.querySelector('.oaldpex-nav');
                if (!nav) throw new Error('Expected the configured Oxford navigation');
                const samples = [];
                for (let frame = 0; frame < 40; frame++) {
                  const style = getComputedStyle(nav);
                  const spans = Array.from(nav.querySelectorAll('span')).map(span => {
                    const style = getComputedStyle(span);
                    return {label:span.textContent,color:style.color,background:style.backgroundColor,active:span.classList.contains('active')};
                  });
                  samples.push({background:style.backgroundColor,color:style.color,spans});
                  await new Promise(resolve => requestAnimationFrame(resolve));
                }
                return samples;
                """#, in: nil, in: .page) { result in
                switch result {
                case let .success(value): samples = value as? [[String: Any]]
                case let .failure(failure): error = failure
                }
            }
        }
        view.lookup("word")
        try await waitForTestCondition("Configured dictionary initial navigation colors are sampled", timeout: .seconds(20), dispatchAppKitEvents: true) { samples != nil || error != nil }
        if let error { throw error }
        let frames = try #require(samples)
        let colors = try frames.map { frame in
            let value: [String: Any] = ["background": frame["background"] ?? "", "color": frame["color"] ?? "", "spans": frame["spans"] ?? [Any]()]
            return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        #expect(Set(colors).count == 1, "Navigation colors changed after reveal: \(colors.first ?? "missing") → \(colors.last ?? "missing")")
    }

    @Test(.timeLimit(.minutes(1)))
    func settlesInitialThemeTransitionsButPreservesLaterInteractionTransitions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumThemeReadiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // OALDPEX changes these navigation colors when its script detects the dark theme.
        // A long duration keeps an unfinished transition observable on a busy test runner.
        let html = #"""
            <style>
              .navigation span {display:inline-block;background:#a5d6a7;color:#2f5932;
                transition:color 60s ease,background-color 60s ease}
              [data-theme="dark"] .navigation span {background:#3a6438;color:#a5c6a0}
              [data-theme="dark"] .navigation span.active {background:#4b8b45;color:#e5e0d8}
            </style>
            <div id="dictionary"><div class="navigation"><span id="entry">Noun</span></div></div>
            <script>
              getComputedStyle(document.getElementById('entry')).backgroundColor;
              requestAnimationFrame(() => {
                document.getElementById('dictionary').setAttribute('data-theme', 'dark');
                getComputedStyle(document.getElementById('entry')).backgroundColor;
              });
            </script>
            """#
        let mdx = directory.appendingPathComponent("fixture.mdx")
        try MDictFixture(entries: [("noun", Data(html.utf8))]).data.write(to: mdx)
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
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.contentView = nil; window.close() }
        var reveal: [String: Any]?
        var error: Error?
        view.onLoadingChange = { [weak view] loading in
            guard !loading, reveal == nil, let view else { return }
            view.webView.evaluateJavaScript(#"""
                (() => {
                  const style = getComputedStyle(document.getElementById('entry'));
                  return {theme:document.getElementById('dictionary').getAttribute('data-theme'),
                    color:style.color,background:style.backgroundColor,
                    transitions:document.getAnimations().filter(a => a instanceof CSSTransition && a.playState !== 'finished').length};
                })();
                """#) { result, failure in
                reveal = result as? [String: Any]
                error = failure
            }
        }
        view.lookup("noun")
        try await waitForTestCondition("Dictionary initial transition state is captured", dispatchAppKitEvents: true) { reveal != nil || error != nil }
        if let error { throw error }
        let shown = try #require(reveal)
        #expect(shown["theme"] as? String == "dark")
        #expect(shown["color"] as? String == "rgb(165, 198, 160)")
        #expect(shown["background"] as? String == "rgb(58, 100, 56)")
        #expect(shown["transitions"] as? Int == 0)

        let later = try await view.webView.callAsyncJavaScript(#"""
            for (const animation of document.getAnimations()) animation.finish();
            const entry = document.getElementById('entry');
            getComputedStyle(entry).backgroundColor;
            entry.classList.add('active');
            getComputedStyle(entry).backgroundColor;
            await new Promise(resolve => requestAnimationFrame(resolve));
            const properties = document.getAnimations().filter(a => a instanceof CSSTransition).map(a => a.transitionProperty);
            for (const animation of document.getAnimations()) animation.finish();
            return properties;
            """#, contentWorld: .page) as? [String]
        #expect(later?.contains("color") == true)
        #expect(later?.contains("background-color") == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func waitsForTheDictionaryScriptBeforeRevealingTheEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumPaintReadiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = "<h1 id='entry'>ready</h1><script src='final.js'></script>"
        let mdx = directory.appendingPathComponent("fixture.mdx")
        try MDictFixture(entries: [("ready", Data(html.utf8))]).data.write(to: mdx)
        // Keep the parser-blocking resource pending so an early reveal is observable.
        let script = String(repeating: "/* dictionary script */\n", count: 40_000)
            + "document.getElementById('entry').style.color = 'rgb(1, 2, 3)';window.dictionaryFinalStyleReady=true;"
        try Data(script.utf8).write(to: directory.appendingPathComponent("final.js"))
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
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.stop(); window.contentView = nil; window.close() }
        var styleAtReveal: String?
        var readyStateAtReveal: String?
        var fontsAtReveal: String?
        var visibilityAtReveal: String?
        var viewportAtReveal: [Double]?
        var error: Error?
        view.onLoadingChange = { [weak view] loading in
            guard !loading, styleAtReveal == nil, let view else { return }
            view.webView.evaluateJavaScript("({state:document.readyState,color:getComputedStyle(document.getElementById('entry')).color,fonts:document.fonts.status,visibility:document.visibilityState,viewport:[innerWidth,innerHeight]})") { result, failure in
                if let values = result as? [String: Any] {
                    readyStateAtReveal = values["state"] as? String
                    styleAtReveal = values["color"] as? String
                    fontsAtReveal = values["fonts"] as? String
                    visibilityAtReveal = values["visibility"] as? String
                    viewportAtReveal = values["viewport"] as? [Double]
                }
                error = failure
            }
        }
        view.lookup("ready")
        try await waitForTestCondition("Dictionary reveal state is captured", dispatchAppKitEvents: true) { styleAtReveal != nil || error != nil }
        if let error { throw error }
        #expect(readyStateAtReveal == "complete")
        #expect(styleAtReveal == "rgb(1, 2, 3)")
        #expect(fontsAtReveal == "loaded")
        #expect(visibilityAtReveal == "visible")
        let viewport = try #require(viewportAtReveal)
        #expect(viewport.count == 2)
        #expect(viewport.first == 600)
        #expect((viewport.last ?? 0) > 0)
        try await waitForTestCondition("Dictionary script finishes", dispatchAppKitEvents: true) { !view.webView.isLoading }
        #expect(try await view.webView.evaluateJavaScript("window.dictionaryFinalStyleReady") as? Bool == true)
    }
}

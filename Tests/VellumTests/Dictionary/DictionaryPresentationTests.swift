import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary presentation", .serialized)
@MainActor
struct DictionaryPresentationTests {
    @Test
    func keepsTheEntryHiddenUntilNavigationCompletionIsForwarded() async throws {
        try await withPopover { view in
            let delegate = DictionaryUnfinishedNavigation()
            view.webView.navigationDelegate = delegate
            view.lookup("short")
            try await waitForTestCondition("Dictionary navigation finishes without forwarding its callback") { delegate.navigation != nil }
            #expect(view.isLoading)
            #expect(try await view.webView.evaluateJavaScript("document.querySelector('.headword').textContent") as? String == "short")
            let navigation = try #require(delegate.navigation)
            view.webView(view.webView, didFinish: navigation)
            try await waitForTestCondition("Completed dictionary content is presented") { !view.isLoading }
            #expect(view.preferredHeight < 180)
        }
    }

    @Test
    func stoppedNavigationCannotRevealTheEntryAfterReadinessWorkCompletes() async throws {
        try await withPopover { view in
            let delegate = DictionaryUnfinishedNavigation()
            view.webView.navigationDelegate = delegate
            var loadingChanges: [Bool] = []
            view.onLoadingChange = { loadingChanges.append($0) }
            view.lookup("short")
            try await waitForTestCondition("Dictionary navigation finishes before readiness work starts") { delegate.navigation != nil }
            let navigation = try #require(delegate.navigation)
            view.webView(view.webView, didFinish: navigation)
            view.stop()
            var finished = false
            var error: Error?
            view.webView.callAsyncJavaScript("""
                await document.fonts.ready;
                await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                return true;
                """, in: nil, in: .page) { result in
                if case let .failure(failure) = result { error = failure }
                finished = true
            }
            try await waitForTestCondition("Cancelled page readiness callbacks finish") { finished }
            if let error { throw error }
            await nextTestMainQueueTurn()
            #expect(loadingChanges == [true])
        }
    }

    @Test
    func contentHeightGrowsAndShrinksIndependentlyOfTheViewport() async throws {
        try await withPopover { view in
            view.lookup("short")
            try await waitForTestCondition("Short dictionary entry has a compact height") {
                !view.isLoading && view.preferredHeight < 180
            }
            #expect(view.preferredHeight >= 160)
            _ = try await view.webView.evaluateJavaScript("document.getElementById('detail').style.height = '400px';null;")
            try await waitForTestCondition("Expanded dictionary content grows the panel") { view.preferredHeight > 450 }
            _ = try await view.webView.evaluateJavaScript("document.getElementById('detail').style.height = '24px';null;")
            try await waitForTestCondition("Collapsed dictionary content shrinks the panel") { view.preferredHeight < 180 }

            view.lookup("long")
            try await waitForTestCondition("Long dictionary entry reports its full height") { !view.isLoading && view.preferredHeight > 2000 }
            view.lookup("short")
            try await waitForTestCondition("A shorter lookup resets the previous content height") {
                !view.isLoading && view.preferredHeight < 180
            }
        }
    }

    @Test
    func hiddenAndClippedDescendantsDoNotAddBlankSpace() async throws {
        try await withPopover { view in
            view.lookup("clipped")
            try await waitForTestCondition("Dictionary content with a closed settings panel is presented") { !view.isLoading }
            #expect(view.preferredHeight < 180)
            _ = try await view.webView.evaluateJavaScript("document.getElementById('overflow').style.overflow = 'visible';null;")
            try await waitForTestCondition("Unclipped overflow contributes its visible height") { view.preferredHeight > 900 }
            _ = try await view.webView.evaluateJavaScript("document.getElementById('overflow').style.overflow = 'hidden';null;")
            try await waitForTestCondition("Clipping the extra content shrinks the panel again") { view.preferredHeight < 180 }
        }
    }

    private func withPopover(_ body: @MainActor (DictionaryPopoverView) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumPresentation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let style = "<style>body{min-height:100vh;margin:30px 0}h1{margin:0;font:16px/20px sans-serif}</style>"
        let short = style + "<h1 class='headword'>short</h1><div id='detail' style='height:24px'>Definition</div>"
        let long = style + "<h1 class='headword'>long</h1><div style='height:2000px'>Long definition</div>"
        let clipped = short + "<div style='position:absolute;top:5px;visibility:hidden;height:0;overflow:hidden'><div style='height:800px'>Closed settings</div></div><div id='overflow' style='position:absolute;top:70px;height:0;overflow:hidden'><div style='height:800px'>Clipped overflow</div></div>"
        let mdx = directory.appendingPathComponent("fixture.mdx")
        try MDictFixture(entries: [("clipped", Data(clipped.utf8)), ("long", Data(long.utf8)), ("short", Data(short.utf8))]).data.write(to: mdx)
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
        try await body(view)
    }
}

@MainActor
private final class DictionaryUnfinishedNavigation: NSObject, WKNavigationDelegate {
    var navigation: WKNavigation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { self.navigation = navigation }
}

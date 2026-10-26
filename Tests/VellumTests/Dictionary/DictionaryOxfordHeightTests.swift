import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@MainActor
@Suite("Oxford dictionary content height", .serialized)
struct DictionaryOxfordHeightTests {
    @Test(.timeLimit(.minutes(1)))
    func configuredTypographyHeightExcludesInvisibleSettings() async throws {
        guard let path = ProcessInfo.processInfo.environment["VELLUM_TEST_MDX_PATH"] else { return }
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
        view.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 560)
        defer { view.stop() }
        view.lookup("typography")
        try await waitForTestCondition("Oxford typography document loaded", timeout: .seconds(20)) {
            !view.isLoading && !view.webView.isLoading
        }
        _ = try await view.webView.callAsyncJavaScript("await document.fonts.ready; return true;", contentWorld: .page)
        let visibleBottom = try #require(try await view.webView.evaluateJavaScript(#"""
            (() => {
              const derivative = document.querySelector('.oald.visible .xrefs[xt="derivative"]');
              const entry = derivative.closest('.oald-entry-root');
              return derivative.getBoundingClientRect().bottom + scrollY + parseFloat(getComputedStyle(entry).marginBottom);
            })();
            """#) as? Double)
        #expect(abs(view.preferredHeight - visibleBottom - 12 - 43) < 3)
    }
}

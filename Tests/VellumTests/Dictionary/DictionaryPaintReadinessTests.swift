import AppKit
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary paint readiness", .serialized)
@MainActor
struct DictionaryPaintReadinessTests {
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

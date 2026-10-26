import AppKit
import AVFoundation
import Testing
@preconcurrency import WebKit
@testable import VellumCore

@Suite("Dictionary recorded pronunciation", .serialized)
@MainActor
struct DictionaryPronunciationTests {
    @Test(.timeLimit(.minutes(1)))
    func automaticPlaybackDefaultsToAmericanAndUsesTheConfiguredBritishRecording() async throws {
        let fixture = try DictionaryPronunciationFixture()
        defer { fixture.close() }
        #expect(AppPreferences.automaticallyPronouncesDictionary())
        #expect(AppPreferences.dictionaryPronunciationAccent() == .american)
        fixture.view.lookup("hello")
        try await fixture.waitForPlayback(fixture.american)
        let american = try #require(fixture.view.player)

        UserDefaults.standard.set(AIPronunciationAccentPreference.british.rawValue, forKey: AppPreferenceKeys.dictionaryPronunciationAccent)
        fixture.view.lookup("hello")
        #expect(!american.isPlaying)
        try await fixture.waitForPlayback(fixture.british)
        let british = try #require(fixture.view.player)
        #expect(british !== american)
        fixture.view.dismiss()
        #expect(!british.isPlaying)
        #expect(fixture.view.player == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func disabledAutoplayAndMissingPreferredRecordingDoNotPlayAnotherAccentOrAnExample() async throws {
        let fixture = try DictionaryPronunciationFixture()
        defer { fixture.close() }
        UserDefaults.standard.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        fixture.view.lookup("hello")
        try await fixture.waitForDocumentAndPendingWork()
        #expect(fixture.view.player == nil)

        UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        fixture.view.lookup("british-only")
        try await fixture.waitForDocumentAndPendingWork()
        #expect(fixture.view.player == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func unfinishedLookupsCannotStartStalePlaybackAfterDismissalOrReplacement() async throws {
        let fixture = try DictionaryPronunciationFixture()
        defer { fixture.close() }
        fixture.view.lookup("stale")
        fixture.view.dismiss()
        try await fixture.drainPendingWork()
        #expect(fixture.view.player == nil)

        fixture.view.lookup("stale")
        fixture.view.lookup("hello")
        try await fixture.waitForPlayback(fixture.american)
        let headword = try await fixture.view.webView.evaluateJavaScript("document.querySelector('.headword').textContent") as? String
        #expect(headword == "hello")
        #expect(fixture.view.player?.data != fixture.stale)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["sound://us.wav", "entry://british-only"])
    func dismissedPagesCannotRestartAudioOrLookUpAnotherEntry(link: String) async throws {
        let fixture = try DictionaryPronunciationFixture()
        defer { fixture.close() }
        UserDefaults.standard.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        let probe = DictionaryNavigationProbe(view: fixture.view)
        fixture.view.webView.navigationDelegate = probe
        fixture.view.lookup("hello")
        try await waitForTestCondition("Dictionary navigation finished") { probe.finished }
        try await waitForTestCondition("Dictionary page is ready for interaction") { !fixture.view.isLoading }
        fixture.view.dismiss()

        _ = try await fixture.view.webView.evaluateJavaScript("location.href='\(link)';null;")
        try await waitForTestCondition("Dismissed page navigation reached the real policy delegate") { !probe.decidedLinks.isEmpty }
        try await fixture.drainPendingWork()
        let restartedAudio = fixture.view.player != nil
        let restartedLookup = probe.startedEntryLookup
        #expect(!restartedAudio)
        #expect(!restartedLookup)
    }

    @Test(.timeLimit(.minutes(1)))
    func activePagesCanPlayRecordedAudioThroughNativeNavigation() async throws {
        let fixture = try DictionaryPronunciationFixture()
        defer { fixture.close() }
        UserDefaults.standard.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        let probe = DictionaryNavigationProbe(view: fixture.view)
        fixture.view.webView.navigationDelegate = probe
        fixture.view.lookup("hello")
        try await waitForTestCondition("Dictionary navigation finished") { probe.finished }
        try await waitForTestCondition("Dictionary page is ready for interaction") { !fixture.view.isLoading }
        #expect(fixture.view.player == nil)

        _ = try await fixture.view.webView.evaluateJavaScript("location.href='sound://us.wav';null;")
        try await waitForTestCondition("Active page navigation reached the real policy delegate") { !probe.decidedLinks.isEmpty }
        try await fixture.waitForPlayback(fixture.american)
    }
}

@MainActor
private final class DictionaryNavigationProbe: NSObject, WKNavigationDelegate {
    let view: DictionaryPopoverView
    var finished = false
    var decidedLinks: [String] = []
    var startedEntryLookup = false

    init(view: DictionaryPopoverView) { self.view = view }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        view.webView(webView, didFinish: navigation)
        finished = webView.url?.scheme == DictionaryPage.scheme
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let link = navigationAction.request.url.flatMap { DictionaryPage.link($0.absoluteString) }
        view.webView(webView, decidePolicyFor: navigationAction) { [self] policy in
            if let link {
                decidedLinks.append(link.kind)
                if link.kind == "entry" { startedEntryLookup = view.isLoading }
            }
            decisionHandler(policy)
        }
    }
}

@MainActor
private final class DictionaryPronunciationFixture {
    let directory: URL
    let american: Data
    let british: Data
    let stale: Data
    let view: DictionaryPopoverView
    private let window: NSWindow
    private static let preferenceKeys = [AppPreferenceKeys.dictionaryPath, AppPreferenceKeys.dictionaryAutoPronunciationEnabled,
                                         AppPreferenceKeys.dictionaryPronunciationAccent]
    private let previousPreferences: [Any?]

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumPronunciation-\(UUID().uuidString)", isDirectory: true)
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let american = Self.silentWAV(seconds: 20)
        let british = Self.silentWAV(seconds: 21)
        let stale = Self.silentWAV(seconds: 22)
        self.american = american
        self.british = british
        self.stale = stale
        let both = "<a class='sound pron-us' href='sound://us.wav'>US</a><a class='sound pron-uk' href='sound://uk.wav'>UK</a>"
        let britishOnly = "<a class='sound pron-uk' href='sound://uk.wav'>UK</a>"
        let old = "<a class='sound pron-us' href='sound://stale.wav'>US</a>"
        let entries = [("british-only", britishOnly), ("hello", both), ("stale", old)].map { word, links in
            (word, Data("<h1 class='headword'>\(word)</h1><div class='examples'><a class='sound pron-us app' href='sound://stale.wav'>Example</a></div><div class='phonetics'>\(links)</div>".utf8))
        }
        let mdx = directory.appendingPathComponent("fixture.mdx")
        try MDictFixture(entries: entries).data.write(to: mdx)
        try MDictFixture(entries: [("\\stale.wav", stale), ("\\uk.wav", british), ("\\us.wav", american)], resource: true)
            .data.write(to: directory.appendingPathComponent("fixture.mdd"))
        let defaults = UserDefaults.standard
        previousPreferences = Self.preferenceKeys.map { defaults.object(forKey: $0) }
        defaults.set(mdx.path, forKey: AppPreferenceKeys.dictionaryPath)
        defaults.removeObject(forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        defaults.removeObject(forKey: AppPreferenceKeys.dictionaryPronunciationAccent)
        let view = DictionaryPopoverView()
        self.view = view
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        self.window = window
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
    }

    func waitForPlayback(_ data: Data) async throws {
        try await waitForTestCondition("Dictionary starts the selected MDD recording") {
            view.player?.data == data && view.player?.isPlaying == true
        }
    }

    func waitForDocumentAndPendingWork() async throws {
        try await waitForTestCondition("Dictionary pronunciation page loaded") { !view.isLoading }
        _ = try await view.webView.evaluateJavaScript("null;")
        try await drainPendingWork()
    }

    func drainPendingWork() async throws {
        await nextTestMainQueueTurn()
        _ = try await DictionaryStore.shared.resource("uk.wav", at: directory.appendingPathComponent("fixture.mdx"))
        await nextTestMainQueueTurn()
    }

    func close() {
        view.stop()
        window.contentView = nil
        window.close()
        let defaults = UserDefaults.standard
        for (key, value) in zip(Self.preferenceKeys, previousPreferences) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func silentWAV(seconds: UInt32) -> Data {
        let sampleRate: UInt32 = 8_000
        let bytes = seconds * sampleRate * 2
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        append(bytes + 36)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(Data("data".utf8))
        append(bytes)
        data.append(Data(repeating: 0, count: Int(bytes)))
        return data
    }
}

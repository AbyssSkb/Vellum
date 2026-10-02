import AppKit
import Foundation
import Testing
import VellumCore
@testable import Vellum

@Suite(.serialized)
@MainActor
struct GitHubUpdateCheckerTests {
    @Test
    func manualConfirmationDownloadsBeforeInstalling() async throws {
        let fixture = UpdateHTTPFixture()
        defer { fixture.finish() }
        var events: [String] = []
        var installedURL: URL?
        let checker = GitHubUpdateChecker(
            session: fixture.session,
            prepareToTerminate: { events.append("save"); return true },
            presentUpdate: { _, _, downloaded in
                #expect(!downloaded)
                events.append("confirm")
                return .install
            },
            installUpdate: { url in events.append("install"); installedURL = url }
        )
        checker.checkForUpdates(.manual)
        try await waitUntil { fixture.downloadCount == 1 }
        #expect(events == ["confirm"])
        #expect(installedURL == nil)
        fixture.completeDownload()
        try await waitUntil { installedURL != nil }
        let url = try #require(installedURL)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == fixture.installerData)
        #expect(events == ["confirm", "save", "install"])
    }

    @Test
    func automaticDownloadWaitsForCompletionAndReusesInstaller() async throws {
        let fixture = UpdateHTTPFixture()
        defer { fixture.finish() }
        var prompts: [Bool] = []
        var installedURL: URL?
        var events: [String] = []
        let checker = GitHubUpdateChecker(
            session: fixture.session,
            prepareToTerminate: { events.append("save"); return true },
            presentUpdate: { _, _, downloaded in
                prompts.append(downloaded)
                return prompts.count == 1 ? .later : .install
            },
            installUpdate: { url in events.append("install"); installedURL = url }
        )

        checker.checkForUpdates(.automatic)
        try await waitUntil { fixture.downloadCount == 1 }
        #expect(prompts.isEmpty)
        #expect(events.isEmpty)
        fixture.completeDownload()
        try await waitUntil { prompts.count == 1 }
        #expect(prompts == [true])
        #expect(events.isEmpty)

        fixture.networkUnavailable = true
        checker.checkForUpdates(.manual)
        try await waitUntil { installedURL != nil }
        let url = try #require(installedURL)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == fixture.installerData)
        #expect(prompts == [true, true])
        #expect(events == ["save", "install"])
        #expect(fixture.downloadCount == 1)
    }

    @Test
    func failedSaveKeepsDownloadedInstallerForRetry() async throws {
        let fixture = UpdateHTTPFixture()
        defer { fixture.finish() }
        var saveAttempts = 0
        var installedURL: URL?
        let checker = GitHubUpdateChecker(
            session: fixture.session,
            prepareToTerminate: { saveAttempts += 1; return saveAttempts > 1 },
            presentUpdate: { _, _, downloaded in #expect(downloaded); return .install },
            installUpdate: { installedURL = $0 }
        )

        checker.checkForUpdates(.automatic)
        try await waitUntil { fixture.downloadCount == 1 }
        fixture.completeDownload()
        try await waitUntil { saveAttempts == 1 }
        #expect(installedURL == nil)

        checker.checkForUpdates(.manual)
        try await waitUntil { installedURL != nil }
        defer { if let installedURL { try? FileManager.default.removeItem(at: installedURL) } }
        #expect(saveAttempts == 2)
        #expect(fixture.downloadCount == 1)
    }

    @Test
    func supersededConfirmationCannotInstall() async throws {
        let fixture = UpdateHTTPFixture()
        defer { fixture.finish() }
        var promptCount = 0
        var installedURL: URL?
        let reference = CheckerReference()
        let checker = GitHubUpdateChecker(
            session: fixture.session,
            prepareToTerminate: { Issue.record("Superseded confirmation attempted to quit"); return true },
            presentUpdate: { _, _, downloaded in
                #expect(downloaded)
                promptCount += 1
                if promptCount == 1 {
                    reference.checker?.checkForUpdates(.manual)
                    return .install
                }
                return .later
            },
            installUpdate: { installedURL = $0 }
        )
        reference.checker = checker

        checker.checkForUpdates(.automatic)
        try await waitUntil { fixture.downloadCount == 1 }
        fixture.completeDownload()
        try await waitUntil { promptCount == 2 }
        #expect(installedURL == nil)
        #expect(fixture.downloadCount == 1)
    }

    @Test
    func manualCheckFindsNewReleaseAfterEarlierDownload() async throws {
        let fixture = UpdateHTTPFixture()
        defer { fixture.finish() }
        var prompts: [(String, Bool)] = []
        let checker = GitHubUpdateChecker(
            session: fixture.session,
            presentUpdate: { update, _, downloaded in
                prompts.append((update.version, downloaded))
                return .later
            },
            installUpdate: { _ in Issue.record("Later attempted installation") }
        )
        checker.checkForUpdates(.automatic)
        try await waitUntil { fixture.downloadCount == 1 }
        fixture.completeDownload()
        try await waitUntil { prompts.count == 1 }
        fixture.version = "v1000.0.0"
        checker.checkForUpdates(.manual)
        try await waitUntil { prompts.count == 2 }
        #expect(prompts[0].0 == "v999.0.0")
        #expect(prompts[0].1)
        #expect(prompts[1].0 == "v1000.0.0")
        #expect(!prompts[1].1)
    }

    @Test
    func backgroundDownloadFailureStaysQuietAndCanRetry() async throws {
        let fixture = UpdateHTTPFixture()
        defer { fixture.finish() }
        fixture.failDownload = true
        var promptCount = 0
        let checker = GitHubUpdateChecker(
            session: fixture.session,
            presentUpdate: { _, _, _ in promptCount += 1; return .later },
            installUpdate: { _ in Issue.record("Failed download attempted installation") }
        )
        checker.checkForUpdates(.automatic)
        try await waitUntil { fixture.downloadCount == 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(promptCount == 0)
        fixture.failDownload = false
        checker.checkForUpdates(.automatic)
        try await waitUntil { fixture.downloadCount == 2 }
        #expect(promptCount == 0)
        fixture.completeDownload()
        try await waitUntil { promptCount == 1 }
    }

    @Test
    func downloadedConfirmationHasLocalizedRestartAction() throws {
        _ = NSApplication.shared
        let key = AppPreferenceKeys.appLanguage
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        for language in AppUILanguage.allCases {
            UserDefaults.standard.set(language.rawValue, forKey: key)
            let controller = UpdateAvailableWindowController(
                updateVersion: "0.7.16", currentVersion: "0.7.15", canInstall: true,
                releaseNotes: [], isDownloaded: true
            )
            let content = try #require(controller.window?.contentView)
            content.layoutSubtreeIfNeeded()
            let views = descendants(of: content)
            let buttons = views.compactMap { ($0 as? NSButton)?.title }
            let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
            #expect(buttons.contains(language.text(.restartAndUpdate)))
            #expect(labels.contains(language.text(.updateReadyTitle("0.7.16"))))
            #expect(!buttons.contains(language.text(.downloadAndInstall)))
            let image = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: image)
            try image.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("vellum-update-ready-\(language.rawValue).png"))
            controller.window?.delegate = nil
            controller.close()
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Update operation timed out")
        throw URLError(.timedOut)
    }
}

@MainActor
private final class CheckerReference {
    weak var checker: GitHubUpdateChecker?
}

private final class UpdateHTTPFixture: @unchecked Sendable {
    static let registry = Registry()
    let installerData = Data("completed installer fixture".utf8)
    let session: URLSession
    private let lock = NSLock()
    private var pending: UpdateURLProtocol?
    private var requests = 0
    private var unavailable = false
    private var fail = false
    private var releaseVersion = "v999.0.0"
    private let previousPromptedVersion: Any?

    var downloadCount: Int { lock.withLock { requests } }
    var networkUnavailable: Bool {
        get { lock.withLock { unavailable } }
        set { lock.withLock { unavailable = newValue } }
    }
    var failDownload: Bool {
        get { lock.withLock { fail } }
        set { lock.withLock { fail = newValue } }
    }
    var version: String {
        get { lock.withLock { releaseVersion } }
        set { lock.withLock { releaseVersion = newValue } }
    }

    @MainActor init() {
        _ = NSApplication.shared
        previousPromptedVersion = UserDefaults.standard.object(forKey: "VellumLastPromptedUpdateVersion")
        UserDefaults.standard.removeObject(forKey: "VellumLastPromptedUpdateVersion")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        session = URLSession(configuration: configuration)
        Self.registry.set(self)
    }

    func finish() {
        session.invalidateAndCancel()
        Self.registry.set(nil)
        UserDefaults.standard.set(previousPromptedVersion, forKey: "VellumLastPromptedUpdateVersion")
    }

    func respond(to request: UpdateURLProtocol) {
        guard let url = request.request.url else { return }
        if networkUnavailable {
            request.client?.urlProtocol(request, didFailWithError: URLError(.notConnectedToInternet))
        } else if url.host == "updates.example" {
            if failDownload {
                request.respond(status: 500, data: Data())
                lock.withLock { requests += 1 }
            } else {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(installerData.count)"])!
                request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
                request.client?.urlProtocol(request, didLoad: installerData.prefix(4))
                lock.withLock { pending = request; requests += 1 }
            }
        } else if url.host == "api.github.com", url.path.hasSuffix("/releases/latest") {
            request.respond(status: 200, data: Data("""
                {"tag_name":"\(version)","html_url":"https://github.com/AbyssSkb/Vellum/releases/tag/\(version)","draft":false,"prerelease":false,"body":"Completed background update","assets":[{"name":"Vellum-\(version)-macOS.dmg","browser_download_url":"https://updates.example/Vellum-\(version)-macOS.dmg"}]}
                """.utf8))
        } else if url.host == "api.github.com", url.path.hasSuffix("/releases") {
            request.respond(status: 200, data: Data("[]".utf8))
        } else {
            request.respond(status: 500, data: Data())
        }
    }

    func completeDownload() {
        guard let request = lock.withLock({ let request = pending; pending = nil; return request }) else { return }
        request.client?.urlProtocol(request, didLoad: installerData.dropFirst(4))
        request.client?.urlProtocolDidFinishLoading(request)
    }

    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var fixture: UpdateHTTPFixture?
        func set(_ fixture: UpdateHTTPFixture?) { lock.withLock { self.fixture = fixture } }
        func get() -> UpdateHTTPFixture? { lock.withLock { fixture } }
    }
}

private final class UpdateURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { UpdateHTTPFixture.registry.get()?.respond(to: self) }
    override func stopLoading() {}

    func respond(status: Int, data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

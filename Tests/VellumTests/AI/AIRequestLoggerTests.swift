import Foundation
import Testing
@testable import VellumCore

@Suite("AI request logger")
struct AIRequestLoggerTests {
    @Test
    func defaultLogDirectoryPreservesProductionAndUnbundledPaths() {
        let appSupport = URL(fileURLWithPath: "/test-support", isDirectory: true)
        let production = appSupport.appendingPathComponent("Vellum/Logs", isDirectory: true)

        #expect(AIRequestLogger.defaultLogsDirectoryURL(
            applicationSupportURL: appSupport, bundleIdentifier: "com.abyssskb.vellum"
        ) == production)
        #expect(AIRequestLogger.defaultLogsDirectoryURL(
            applicationSupportURL: appSupport, bundleIdentifier: nil
        ) == production)
    }

    @Test
    func defaultLogDirectoryIsolatesPreviewIdentities() {
        let appSupport = URL(fileURLWithPath: "/test-support", isDirectory: true)
        let first = AIRequestLogger.defaultLogsDirectoryURL(
            applicationSupportURL: appSupport, bundleIdentifier: "com.abyssskb.vellum.preview.first"
        )
        let second = AIRequestLogger.defaultLogsDirectoryURL(
            applicationSupportURL: appSupport, bundleIdentifier: "com.abyssskb.vellum.preview.second"
        )

        #expect(first == appSupport.appendingPathComponent("com.abyssskb.vellum.preview.first/Logs", isDirectory: true))
        #expect(second == appSupport.appendingPathComponent("com.abyssskb.vellum.preview.second/Logs", isDirectory: true))
        #expect(first != second)
        #expect(first != appSupport.appendingPathComponent("Vellum/Logs", isDirectory: true))
        #expect(second != appSupport.appendingPathComponent("Vellum/Logs", isDirectory: true))
    }

    @Test
    func openLogReportsRejectedLaunch() throws {
        var openedURL: URL?

        do {
            try AIRequestLogger.openLog {
                openedURL = $0
                return false
            }
            Issue.record("Opening a log rejected by the system must report an error")
        } catch {
            #expect(error.localizedDescription == AppUILanguage.saved().text(.aiLogOpenRejected))
        }

        #expect(openedURL == AIRequestLogger.logFileURL)
        let fileURL = try #require(openedURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func sanitizedHeadersRedactSecrets() {
        let headers = AIRequestLogger.sanitizedHeaders([
            "Authorization": "Bearer secret",
            "x-api-key": "secret-key",
            "Content-Type": "application/json"
        ])

        #expect(headers["Authorization"] == "<redacted>")
        #expect(headers["x-api-key"] == "<redacted>")
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test
    func sanitizedURLRedactsCredentialsAndAllQueryValues() throws {
        let url = try #require(URL(string: "https://us%65r:p%40ss@example.test:8443/v1/chat%20completions?api_key=secret&mode=debug&api_key=sec%72et%26nested%3Dvalue&empty=&flag"))

        let sanitized = try #require(AIRequestLogger.sanitizedURL(url))
        let components = try #require(URLComponents(string: sanitized))

        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.host == "example.test")
        #expect(components.port == 8443)
        #expect(components.percentEncodedPath == "/v1/chat%20completions")
        #expect(components.queryItems == [
            URLQueryItem(name: "api_key", value: "<redacted>"),
            URLQueryItem(name: "mode", value: "<redacted>"),
            URLQueryItem(name: "api_key", value: "<redacted>"),
            URLQueryItem(name: "empty", value: "<redacted>"),
            URLQueryItem(name: "flag", value: nil)
        ])
    }

    @Test
    func sanitizedURLPreservesPlainURLsAndMissingURL() throws {
        let url = try #require(URL(string: "https://example.test/v1/models"))

        #expect(AIRequestLogger.sanitizedURL(url) == url.absoluteString)
        #expect(AIRequestLogger.sanitizedURL(nil) == nil)
    }

    @Test
    func textPreviewPrettyPrintsJSON() throws {
        let data = Data(#"{"model":"test","messages":[{"role":"user","content":"hello"}]}"#.utf8)

        let preview = try #require(AIRequestLogger.textPreview(from: data, maxCharacters: 200))

        let object = try #require(JSONSerialization.jsonObject(with: Data(preview.utf8)) as? [String: Any])
        #expect(object["model"] as? String == "test")
        #expect(object["messages"] as? [[String: String]] == [["role": "user", "content": "hello"]])
        #expect(preview.contains("\n"))
    }

    @Test
    func textPreviewLimitsLength() throws {
        let text = String(repeating: "a🪁", count: 50)
        let preview = try #require(AIRequestLogger.textPreview(from: Data(text.utf8), maxCharacters: 40))

        #expect(preview.hasPrefix(String(text.prefix(40))))
        #expect(preview.contains("<truncated 60 characters>"))
        #expect(preview.count < text.count)
    }
}

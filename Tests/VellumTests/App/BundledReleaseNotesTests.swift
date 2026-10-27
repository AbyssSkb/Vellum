import Foundation
import Testing
@testable import VellumCore

@Suite("Bundled release notes")
struct BundledReleaseNotesTests {
    @Test
    func loadsEveryNoteForTheInstalledVersion() throws {
        let notes = (1...12).map { "- Change \($0)." }.joined(separator: "\n")
        let url = try makeBundle(version: "0.8.17", files: ["ReleaseNotes-0.8.17.md": "## What's Changed\n\n\(notes)"])
        defer { try? FileManager.default.removeItem(at: url) }
        let bundle = try #require(Bundle(url: url))

        #expect(AppBundledReleaseNotes.sections(bundle: bundle) == [
            AppReleaseNotesSection(version: nil, notes: (1...12).map { "Change \($0)." })
        ])
    }

    @Test
    func neverUsesAnotherVersionsNotes() throws {
        let url = try makeBundle(version: "0.8.17", files: ["ReleaseNotes-0.8.16.md": "- Old change."])
        defer { try? FileManager.default.removeItem(at: url) }
        let bundle = try #require(Bundle(url: url))

        #expect(AppBundledReleaseNotes.sections(bundle: bundle).isEmpty)
    }

    @Test
    func developmentBundlesWithoutNotesAreEmpty() throws {
        let url = try makeBundle(version: nil, files: [:])
        defer { try? FileManager.default.removeItem(at: url) }
        let bundle = try #require(Bundle(url: url))

        #expect(AppBundledReleaseNotes.sections(bundle: bundle).isEmpty)
    }

    @Test
    func preservesVersionSectionsWithoutTheEightNoteLimit() throws {
        let notes = (1...10).map { "- Change \($0)." }.joined(separator: "\n")
        let url = try makeBundle(version: "0.8.17", files: ["ReleaseNotes-0.8.17.md": "## v0.8.17\n\(notes)"])
        defer { try? FileManager.default.removeItem(at: url) }
        let bundle = try #require(Bundle(url: url))

        #expect(AppBundledReleaseNotes.sections(bundle: bundle) == [
            AppReleaseNotesSection(version: "v0.8.17", notes: (1...10).map { "Change \($0)." })
        ])
    }

    private func makeBundle(version: String?, files: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VellumNotes-\(UUID()).app")
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        var info = ["CFBundleIdentifier": "com.vellum.tests.release-notes", "CFBundleName": "Vellum"]
        info["CFBundleShortVersionString"] = version
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        for (name, text) in files {
            try text.write(to: resources.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return url
    }
}

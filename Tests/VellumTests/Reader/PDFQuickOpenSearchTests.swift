import Darwin
import Foundation
import Testing
@testable import VellumCore

@Suite("PDF quick-open matching")
@MainActor
struct PDFQuickOpenSearchTests {
    @Test
    func pendingQueryKeepsResultsUntilReplacementArrives() async throws {
        let fixture = try ExecutableFixture(script: "/bin/sleep 0.15\n/bin/cat")
        defer { fixture.cleanup() }
        let paths = [URL(fileURLWithPath: "/tmp/DeepSeek-V2.pdf")]
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: paths)
        search.beginSearching()
        search.query = "DeepSeek"
        #expect(search.isSearching)
        #expect(search.results == paths)
        try await waitForTestCondition("New results replace the displayed snapshot") { !search.isSearching }
        #expect(search.results == paths)
        search.endSearching()
    }

    @Test
    func onlyIncludesPDFExtensionsAndExcludesDirectories() throws {
        let fixture = try ExecutableFixture(script: "/bin/cat")
        defer { fixture.cleanup() }
        let pdf = fixture.directory.appendingPathComponent("paper.PDF")
        let directory = fixture.directory.appendingPathComponent("folder.pdf", isDirectory: true)
        let directoryLink = fixture.directory.appendingPathComponent("folder-link.PDF")
        let fileLink = fixture.directory.appendingPathComponent("file-link.pdf")
        try Data().write(to: pdf)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: directory)
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: pdf)
        let paths = [pdf, directory, directoryLink, fileLink, URL(fileURLWithPath: "/tmp/paper.txt"), URL(fileURLWithPath: "/tmp/no-extension")]
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: paths)
        search.beginSearching()
        #expect(search.results == [pdf, fileLink])
        search.endSearching()
    }

    @Test
    func preservesNULSeparatedUnicodeSpacesAndNewlines() async throws {
        let fixture = try ExecutableFixture(script: "/bin/cat")
        defer { fixture.cleanup() }
        let paths = ["/论文/注意力 机制.pdf", "/tmp/line\nbreak.pdf", "/tmp/tab\tname.pdf"].map {
            URL(fileURLWithPath: $0)
        }
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: paths)
        search.beginSearching()
        #expect(search.results == paths)
        search.query = "query"
        try await waitForTestCondition("NUL-separated results return intact") { !search.isSearching }
        #expect(search.results == paths)
        #expect(search.failure == nil)
        #expect(!search.isLoading)
        search.endSearching()
    }

    @Test
    func exitOneMeansNoMatches() async throws {
        let fixture = try ExecutableFixture(script: "/bin/cat >/dev/null\nexit 1")
        defer { fixture.cleanup() }
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: [URL(fileURLWithPath: "/tmp/test.pdf")])
        search.beginSearching()
        search.query = "unmatched"
        try await waitForTestCondition("No-match process finishes") { !search.isSearching }
        #expect(search.results.isEmpty)
        #expect(search.failure == nil)
    }

    @Test
    func reportsMissingExecutableAndMatchingErrors() async throws {
        let missing = PDFQuickOpenSearch(executableURL: nil, initialPaths: [])
        missing.beginSearching()
        #expect(missing.failure == .fzfMissing)
        #expect(!missing.isSearching)

        let fixture = try ExecutableFixture(script: "/bin/cat >/dev/null\nprintf 'synthetic matching error' >&2\nexit 2")
        defer { fixture.cleanup() }
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: [URL(fileURLWithPath: "/tmp/test.pdf")])
        search.beginSearching()
        search.query = "query"
        try await waitForTestCondition("Matching error is reported") { !search.isSearching }
        #expect(search.failure == .matchingFailed("synthetic matching error"))
        #expect(search.results.isEmpty)
    }

    @Test
    func cancelsOldProcessesAndDoesNotMatchWhileClosed() async throws {
        let fixture = try ExecutableFixture(script: """
        if [ "$4" = '--filter=old' ]; then
            printf '%s' "$$" > "$0.pid"
            /bin/sleep 0.2
            printf '/tmp/old.pdf\\0'
        else
            /bin/cat >/dev/null
            printf '/tmp/new.pdf\\0'
        fi
        """
        )
        defer { fixture.cleanup() }
        let marker = URL(fileURLWithPath: fixture.url.path + ".pid")
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: [URL(fileURLWithPath: "/tmp/new.pdf")])
        search.beginSearching()
        search.query = "old"
        try await waitForTestCondition("Old matching process has started") { FileManager.default.fileExists(atPath: marker.path) }
        let pidText = try String(contentsOf: marker, encoding: .utf8)
        let pid = try #require(Int32(pidText))
        search.query = "new"
        try await waitForTestCondition("Latest query replaces the cancelled process") {
            !search.isSearching && search.results == [URL(fileURLWithPath: "/tmp/new.pdf")]
        }
        try await waitForTestCondition("Cancelled subprocess has exited") { kill(pid, 0) != 0 }
        #expect(search.failure == nil)
        search.endSearching()
        search.query = "old"
        #expect(!search.isSearching)
        #expect(search.results.isEmpty)
        search.beginSearching()
        #expect(search.query.isEmpty)
        #expect(search.results == [URL(fileURLWithPath: "/tmp/new.pdf")])
        search.endSearching()
    }

    @Test
    func concurrentlyDrainsOutputAndDiagnosticsWhileWritingInput() async throws {
        let fixture = try ExecutableFixture(script: "/bin/dd if=/dev/zero bs=65536 count=2 >&2\n/bin/cat")
        defer { fixture.cleanup() }
        let paths = (0..<5_000).map { URL(fileURLWithPath: "/tmp/\($0)-a-long-enough-file-name-to-fill-the-pipe.pdf") }
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: paths)
        search.beginSearching()
        search.query = "query"
        try await waitForTestCondition("Large input and both output pipes finish") { !search.isSearching }
        #expect(search.results == paths)
        #expect(search.failure == nil)
    }

    @Test
    func repeatedShortLivedProcessesAlwaysDeliverTheirExitStatus() async throws {
        let fixture = try ExecutableFixture(script: "/bin/cat >/dev/null\nprintf 'short-lived' >&2\nexit 2")
        defer { fixture.cleanup() }
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: [URL(fileURLWithPath: "/tmp/test.pdf")])
        search.beginSearching()
        for iteration in 0..<64 {
            search.query = "query-\(iteration)"
            try await waitForTestCondition("Short-lived process \(iteration) delivers its status") { !search.isSearching }
            #expect(search.failure == .matchingFailed("short-lived"))
        }
        search.endSearching()
    }

    @Test
    func successfulRetryClearsAMissingExecutableFailure() async throws {
        let fixture = try ExecutableFixture(script: "/bin/cat")
        defer { fixture.cleanup() }
        let executable = try Data(contentsOf: fixture.url)
        let paths = [URL(fileURLWithPath: "/tmp/test.pdf")]
        let search = PDFQuickOpenSearch(executableURL: fixture.url, initialPaths: paths)
        search.beginSearching()
        try FileManager.default.removeItem(at: fixture.url)
        search.query = "missing"
        try await waitForTestCondition("Removed executable is reported") { !search.isSearching }
        #expect(search.failure == .fzfMissing)
        try executable.write(to: fixture.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.url.path)
        search.query = "restored"
        try await waitForTestCondition("Restored executable matches successfully") { !search.isSearching }
        #expect(search.failure == nil)
        #expect(search.results == paths)
        search.endSearching()
    }

    @Test
    func installedFZFMatchesPathsAndReturnsNoMatches() async throws {
        guard let executableURL = PDFQuickOpenMatchProcess.findExecutable() else { return }
        let chinese = URL(fileURLWithPath: "/论文/注意力 机制.pdf")
        let newline = URL(fileURLWithPath: "/tmp/line\nbreak.pdf")
        let search = PDFQuickOpenSearch(executableURL: executableURL, initialPaths: [chinese, newline])
        search.beginSearching()
        search.query = "注意 机制"
        try await waitForTestCondition("Installed fzf matches Chinese path fragments") { !search.isSearching }
        #expect(search.results == [chinese])
        search.query = "lnbrk"
        try await waitForTestCondition("Installed fzf preserves newlines in file names") { !search.isSearching }
        #expect(search.results == [newline])
        search.query = "not-present-in-any-path"
        try await waitForTestCondition("Installed fzf reports no matches") { !search.isSearching }
        #expect(search.results.isEmpty)
        #expect(search.failure == nil)
        search.endSearching()
    }

    private struct ExecutableFixture {
        let directory: URL
        let url: URL

        init(script: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("VellumQuickOpen-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("fzf")
            try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

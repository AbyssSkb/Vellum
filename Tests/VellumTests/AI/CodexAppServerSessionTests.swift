import Foundation
import Testing
@testable import VellumCore

@Suite("Codex app-server session lifetime")
struct CodexAppServerSessionTests {
    @Test(arguments: [false, true])
    func stalledProcessStopsOnTimeoutOrCancellation(cancel: Bool) async throws {
        let (directory, configuration) = try stalledServer()
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = ContinuousClock.now
        let request = Task {
            try await CodexAppServerAIExplanationClient().withAppServerSession(
                configuration: configuration,
                timeout: cancel ? 10 : 0.15
            ) { session in
                try await session.readMessages { _ in false }
            }
        }
        if cancel {
            try await Task.sleep(for: .milliseconds(150))
            request.cancel()
        }
        do {
            try await request.value
            Issue.record("A stalled server must not complete successfully")
        } catch is CancellationError {
            #expect(cancel)
        } catch {
            #expect(!cancel)
            #expect(error.localizedDescription.contains("超时"))
        }
        #expect(started.duration(to: .now) < .seconds(2))
    }

    @Test
    func concurrentStderrReadersDoNotDelayTimeouts() async throws {
        let (directory, configuration) = try stalledServer()
        defer { try? FileManager.default.removeItem(at: directory) }
        await withTaskGroup(of: Void.self) { group in
            // Saturate the cooperative pool even on Macs with more cores than CI.
            for _ in 0...ProcessInfo.processInfo.activeProcessorCount {
                group.addTask {
                    let started = ContinuousClock.now
                    do {
                        try await CodexAppServerAIExplanationClient().withAppServerSession(
                            configuration: configuration,
                            timeout: 0.15
                        ) { session in
                            try await session.readMessages { _ in false }
                        }
                        Issue.record("A stalled server must time out")
                    } catch {
                        #expect(error.localizedDescription.contains("超时"))
                    }
                    #expect(started.duration(to: .now) < .seconds(2))
                }
            }
        }
    }

    private func stalledServer() throws -> (URL, AIConfiguration) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("stalled-server")
        // A real process holding stdout open, including when sent SIGTERM.
        try "#!/bin/sh\ntrap '' TERM\nexec /bin/sleep 3\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = try AIConfiguration(baseURLString: executable.path, model: "", apiKey: "", providerFormat: .codexCLI)
        return (directory, configuration)
    }
}

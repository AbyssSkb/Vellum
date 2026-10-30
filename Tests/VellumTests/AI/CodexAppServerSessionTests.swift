import Foundation
import Testing
@testable import VellumCore

@Suite("Codex app-server session lifetime")
struct CodexAppServerSessionTests {
    @Test
    func cancelledReaderReportsCancellationAfterPipeCloses() async throws {
        let (directory, configuration) = try stalledServer()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try CodexAppServerSession(configuration: configuration)
        defer { session.stop() }
        let request = Task {
            try? await Task.sleep(for: .seconds(10))
            try await session.readMessages { _ in false }
        }
        session.stop()
        request.cancel()
        do {
            try await request.value
            Issue.record("The cancelled reader must not complete successfully")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected cancellation, got \(error)")
        }

        do {
            try await session.readMessages { _ in false }
            Issue.record("A stopped session must not complete successfully")
        } catch AIExplanationError.transport(let message) {
            #expect(message == AppUILanguage.saved().text(.codexConnectionClosed))
        }
    }

    @Test(arguments: [false, true])
    func stalledProcessStopsOnTimeoutOrCancellation(cancel: Bool) async throws {
        let (directory, configuration) = try stalledServer()
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = ContinuousClock.now
        let ready = AsyncStream<Void>.makeStream()
        let request = Task {
            try await CodexAppServerAIExplanationClient().withAppServerSession(
                configuration: configuration,
                timeout: cancel ? 10 : 0.15
            ) { session in
                try await session.readMessages { message in
                    if message["ready"] as? Bool == true {
                        ready.continuation.yield()
                        ready.continuation.finish()
                    }
                    return false
                }
            }
        }
        defer {
            request.cancel()
            ready.continuation.finish()
        }
        if cancel {
            try await waitForServerReadiness(ready.stream)
            request.cancel()
        }
        do {
            try await request.value
            Issue.record("A stalled server must not complete successfully")
        } catch is CancellationError {
            #expect(cancel)
        } catch AIExplanationError.transport(let message) {
            #expect(!cancel)
            #expect(message == AppUILanguage.saved().text(.codexRequestTimedOut))
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
                    } catch AIExplanationError.transport(let message) {
                        #expect(message == AppUILanguage.saved().text(.codexRequestTimedOut))
                    } catch {
                        Issue.record(error)
                    }
                    #expect(started.duration(to: .now) < .seconds(2))
                }
            }
        }
    }

    @Test(arguments: [false, true], [false, true])
    func descendantsStopAfterTimeoutOrCancellation(cancel: Bool, wrapperExits: Bool) async throws {
        let (directory, configuration) = try descendantServer(wrapperExits: wrapperExits)
        defer { cleanUpDescendant(in: directory) }
        let session = try CodexAppServerSession(configuration: configuration)
        defer { session.stop() }
        try await waitForDescendant(in: directory)
        let started = ContinuousClock.now
        let ready = AsyncStream<Void>.makeStream()
        let request = Task {
            try await CodexAppServerAIExplanationClient().withAppServerSession(
                session: session,
                timeout: cancel ? 10 : 0.15
            ) { session in
                try await session.readMessages { message in
                    if message["ready"] as? Bool == true {
                        ready.continuation.yield()
                        ready.continuation.finish()
                    }
                    return false
                }
            }
        }
        defer {
            request.cancel()
            ready.continuation.finish()
        }
        if cancel {
            try await waitForServerReadiness(ready.stream)
            request.cancel()
        }
        do {
            try await request.value
            Issue.record("A server whose descendant holds the pipes must not complete successfully")
        } catch is CancellationError {
            #expect(cancel)
        } catch AIExplanationError.transport(let message) {
            #expect(!cancel)
            #expect(message == AppUILanguage.saved().text(.codexRequestTimedOut))
        }
        #expect(started.duration(to: .now) < .seconds(2))
        try await expectDescendantStopped(in: directory)
    }

    @Test
    func successfulRequestAlsoStopsDescendants() async throws {
        let (directory, configuration) = try descendantServer(wrapperExits: true, sendsResponse: true)
        defer { cleanUpDescendant(in: directory) }
        let result = try await CodexAppServerAIExplanationClient().withAppServerSession(
            configuration: configuration,
            timeout: 2
        ) { session in
            try await session.readMessages { message in message["id"] as? Int == 1 }
            return "OK"
        }
        #expect(result == "OK")
        try await expectDescendantStopped(in: directory)
    }

    private func descendantServer(wrapperExits: Bool, sendsResponse: Bool = false) throws -> (URL, AIConfiguration) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("descendant-server")
        let childPath = directory.appendingPathComponent("child-pid").path
        let script = """
        #!/bin/sh
        /bin/sleep 30 &
        echo $! > '\(childPath).tmp'
        /bin/mv '\(childPath).tmp' '\(childPath)'
        echo '{"ready":true}'
        \(sendsResponse ? "echo '{\"id\":1}'" : "")
        \(wrapperExits ? "exit 0" : "wait")
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = try AIConfiguration(baseURLString: executable.path, model: "", apiKey: "", providerFormat: .codexCLI)
        return (directory, configuration)
    }

    private func waitForServerReadiness(_ messages: AsyncStream<Void>) async throws {
        let ready = try await withThrowingTaskGroup(of: Bool.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                for await _ in messages { return true }
                return false
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return false
            }
            return try await group.next() ?? false
        }
        try #require(ready, "The request must consume the server's ready message before cancellation")
    }

    private func waitForDescendant(in directory: URL) async throws {
        // Setup can compete with the concurrent launch saturation test; time only teardown.
        let childPath = directory.appendingPathComponent("child-pid").path
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: childPath), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try descendantPID(in: directory)
    }

    private func expectDescendantStopped(in directory: URL) async throws {
        let pid = try descendantPID(in: directory)
        // Orphaned children need a moment to be reaped after the process group is killed.
        let deadline = ContinuousClock.now + .seconds(2)
        while kill(pid, 0) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let result = kill(pid, 0)
        let error = errno
        #expect(result == -1 && error == ESRCH)
    }

    private func descendantPID(in directory: URL) throws -> pid_t {
        let text = try String(contentsOf: directory.appendingPathComponent("child-pid"), encoding: .utf8)
        return try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func cleanUpDescendant(in directory: URL) {
        if let pid = try? descendantPID(in: directory) { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: directory)
    }

    private func stalledServer() throws -> (URL, AIConfiguration) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("stalled-server")
        // A real process holding stdout open, including when sent SIGTERM.
        try "#!/bin/sh\ntrap '' TERM\necho '{\"ready\":true}'\nexec /bin/sleep 3\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = try AIConfiguration(baseURLString: executable.path, model: "", apiKey: "", providerFormat: .codexCLI)
        return (directory, configuration)
    }
}

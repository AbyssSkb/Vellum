import Foundation

struct CodexAppServerAIExplanationClient: AIExplaining {
    func testConnection(configuration: AIConfiguration) async throws -> String {
        let models = try await fetchModels(configuration: configuration)
        return models.isEmpty
            ? AppUILanguage.saved().text(.codexAvailableNoModels)
            : AppUILanguage.saved().text(.codexAvailableModels(models.count))
    }

    func testFunction(configuration: AIConfiguration) async throws -> String {
        let text = try await runTurn(
            operation: "codex.testFunction",
            prompt: "Reply with OK.",
            configuration: configuration,
            timeout: 90,
            onChunk: nil
        )
        return AppUILanguage.saved().text(.codexResponded(text))
    }

    func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        let startedAt = Date()
        do {
            let models = try await withAppServerSession(configuration: configuration, timeout: 45) { session in
                try session.send([
                    "id": 0,
                    "method": "initialize",
                    "params": initializeParams
                ])

                var didInitialize = false
                var models: [String] = []

                try await session.readMessages { message in
                    if let error = CodexAppServerMessageParser.errorMessage(from: message) {
                        throw AIExplanationError.server(error)
                    }

                    if CodexAppServerMessageParser.responseID(from: message) == 0 {
                        didInitialize = true
                        try session.send(["method": "initialized", "params": [:]])
                        try session.send([
                            "id": 1,
                            "method": "model/list",
                            "params": [
                                "includeHidden": false,
                                "limit": 100
                            ]
                        ])
                        return false
                    }

                    if didInitialize, CodexAppServerMessageParser.responseID(from: message) == 1 {
                        models = CodexAppServerMessageParser.modelIDs(from: message)
                        return true
                    }

                    return false
                }

                return models
            }

            AIRequestLogger.recordLocal(
                operation: "codex.fetchModels",
                configuration: configuration,
                responseText: "Models: \(models.joined(separator: ", "))",
                startedAt: startedAt
            )
            return models
        } catch {
            AIRequestLogger.recordLocal(
                operation: "codex.fetchModels",
                configuration: configuration,
                startedAt: startedAt,
                error: error
            )
            throw error
        }
    }

    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        try await runTurn(
            operation: "codex.explain",
            prompt: explanationPrompt(for: context),
            configuration: configuration,
            timeout: 180,
            onChunk: nil
        )
    }

    func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await runTurn(
            operation: "codex.streamExplanation",
            prompt: explanationPrompt(for: context),
            configuration: configuration,
            timeout: 180,
            onChunk: onChunk
        )
    }

    func streamConversation(
        context: AIExplanationContext,
        messages: [AIConversationMessage],
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await runTurn(
            operation: "codex.streamConversation",
            prompt: AIConversationPromptRenderer.transcriptPrompt(
                context: context,
                messages: messages
            ),
            configuration: configuration,
            timeout: 180,
            onChunk: onChunk
        )
    }

    private var initializeParams: [String: Any] {
        [
            "clientInfo": [
                "name": "vellum",
                "title": "Vellum",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            ],
            "capabilities": [
                "experimentalApi": true
            ]
        ]
    }

    private func runTurn(
        operation: String,
        prompt: String,
        configuration: AIConfiguration,
        timeout: TimeInterval,
        onChunk: (@MainActor (String) -> Void)?
    ) async throws -> String {
        let startedAt = Date()
        do {
            let text = try await withAppServerSession(configuration: configuration, timeout: timeout) { session in
                try session.send([
                    "id": 0,
                    "method": "initialize",
                    "params": initializeParams
                ])

                var threadID: String?
                var turnID: String?
                var streamedText = ""
                var completedText = ""

                try await session.readMessages { message in
                    if let error = CodexAppServerMessageParser.errorMessage(from: message) {
                        throw AIExplanationError.server(error)
                    }

                    if CodexAppServerMessageParser.responseID(from: message) == 0 {
                        try session.send(["method": "initialized", "params": [:]])
                        try session.send([
                            "id": 1,
                            "method": "thread/start",
                            "params": threadStartParams(configuration: configuration)
                        ])
                        return false
                    }

                    if CodexAppServerMessageParser.responseID(from: message) == 1 {
                        guard let id = CodexAppServerMessageParser.threadID(from: message) else {
                            throw AIExplanationError.transport(AppUILanguage.saved().text(.codexMissingThreadID))
                        }
                        threadID = id
                        try session.send([
                            "id": 2,
                            "method": "turn/start",
                            "params": turnStartParams(
                                threadID: id,
                                prompt: prompt,
                                configuration: configuration
                            )
                        ])
                        return false
                    }

                    if CodexAppServerMessageParser.responseID(from: message) == 2 {
                        turnID = CodexAppServerMessageParser.turnID(from: message)
                        return false
                    }

                    if let delta = CodexAppServerMessageParser.agentMessageDelta(from: message, threadID: threadID, turnID: turnID) {
                        streamedText += delta
                        if let onChunk {
                            await MainActor.run {
                                onChunk(delta)
                            }
                        }
                        return false
                    }

                    if let text = CodexAppServerMessageParser.completedAgentMessage(from: message, threadID: threadID, turnID: turnID) {
                        completedText = text
                        return false
                    }

                    if try CodexAppServerMessageParser.isTurnCompleted(message, threadID: threadID, turnID: turnID) {
                        return true
                    }

                    return false
                }

                let text = completedText.nilIfEmpty ?? streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw AIExplanationError.emptyResponse
                }
                return text
            }

            AIRequestLogger.recordLocal(
                operation: operation,
                configuration: configuration,
                prompt: prompt,
                responseText: text,
                startedAt: startedAt
            )
            return text
        } catch {
            AIRequestLogger.recordLocal(
                operation: operation,
                configuration: configuration,
                prompt: prompt,
                startedAt: startedAt,
                error: error
            )
            throw error
        }
    }

    private func threadStartParams(configuration: AIConfiguration) -> [String: Any] {
        var params: [String: Any] = [
            "ephemeral": true,
            "cwd": FileManager.default.homeDirectoryForCurrentUser.path,
            "environments": []
        ]

        if !configuration.model.isEmpty {
            params["model"] = configuration.model
        }

        return params
    }

    private func turnStartParams(threadID: String, prompt: String, configuration: AIConfiguration) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [
                [
                    "type": "text",
                    "text": prompt
                ]
            ],
            "cwd": FileManager.default.homeDirectoryForCurrentUser.path,
            "environments": []
        ]

        if !configuration.model.isEmpty {
            params["model"] = configuration.model
        }

        return params
    }

    private func explanationPrompt(for context: AIExplanationContext) -> String {
        AIPromptRenderer.render(context: context).combined
    }

    func withAppServerSession<T: Sendable>(
        configuration: AIConfiguration,
        timeout: TimeInterval,
        operation: @escaping @Sendable (CodexAppServerSession) async throws -> T
    ) async throws -> T {
        let session = try CodexAppServerSession(configuration: configuration)
        return try await withAppServerSession(session: session, timeout: timeout, operation: operation)
    }

    func withAppServerSession<T: Sendable>(
        session: CodexAppServerSession,
        timeout: TimeInterval,
        operation: @escaping @Sendable (CodexAppServerSession) async throws -> T
    ) async throws -> T {
        defer { session.stop() }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                defer {
                    group.cancelAll()
                    // Close the process before the group waits for its pipe-reading child.
                    session.stop()
                }
                group.addTask {
                    try Task.checkCancellation()
                    return try await operation(session)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw AIExplanationError.transport(AppUILanguage.saved().text(.codexRequestTimedOut))
                }

                guard let result = try await group.next() else {
                    throw AIExplanationError.transport(AppUILanguage.saved().text(.codexRequestIncomplete))
                }
                try Task.checkCancellation()
                return result
            }
        } onCancel: {
            session.stop()
        }
    }
}

final class CodexAppServerSession: @unchecked Sendable {
    private let process: Process
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrTask: Task<String, Never>
    private let stopLock = NSLock()
    private var processGroup: pid_t?
    private var isStopped = false

    init(configuration: AIConfiguration) throws {
        let executablePath = configuration.codexExecutablePath
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw AIExplanationError.transport(AppUILanguage.saved().text(.codexNotExecutable(executablePath)))
        }

        process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = Self.arguments(configuration: configuration)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stderrTask = Task.detached { [stderrPipe] in
            await withCheckedContinuation { continuation in
                // A silent child must not occupy a Swift cooperative worker until it exits.
                DispatchQueue.global(qos: .utility).async {
                    let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                }
            }
        }

        do {
            try process.run()
            let pid = process.processIdentifier
            // Foundation launches a separate group. It can outlive a shell wrapper.
            if pid != getpgrp(), getpgid(pid) == pid || kill(-pid, 0) == 0 {
                processGroup = pid
            }
        } catch {
            try? stderrPipe.fileHandleForWriting.close()
            throw AIExplanationError.transport(AppUILanguage.saved().text(.codexStartFailed(error.localizedDescription)))
        }
    }

    func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)

        try Task.checkCancellation()
        try stdinPipe.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
    }

    func readMessages(until shouldStop: ([String: Any]) async throws -> Bool) async throws {
        for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
            try Task.checkCancellation()
            guard let message = CodexAppServerMessageParser.message(from: line) else { continue }
            if try await shouldStop(message) {
                return
            }
        }

        try Task.checkCancellation()
        let stderr = await stderrTask.value
        throw AIExplanationError.transport(
            stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? AppUILanguage.saved().text(.codexConnectionClosed)
        )
    }

    func stop() {
        stopLock.lock()
        defer { stopLock.unlock() }
        guard !isStopped else { return }
        isStopped = true

        if let processGroup {
            kill(-processGroup, SIGKILL)
        } else if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        try? stdinPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }

    private static func arguments(configuration: AIConfiguration) -> [String] {
        var arguments: [String] = []
        if !configuration.codexProfile.isEmpty {
            arguments.append(contentsOf: ["--profile", configuration.codexProfile])
        }
        arguments.append("app-server")
        return arguments
    }
}

enum CodexAppServerMessageParser {
    static func message(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func responseID(from message: [String: Any]) -> Int? {
        message["id"] as? Int
    }

    static func errorMessage(from message: [String: Any]) -> String? {
        if let error = message["error"] as? [String: Any] {
            return error["message"] as? String
        }
        guard message["method"] as? String == "error",
              let params = message["params"] as? [String: Any],
              params["willRetry"] as? Bool != true,
              let error = params["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    static func modelIDs(from message: [String: Any]) -> [String] {
        guard let result = message["result"] as? [String: Any],
              let data = result["data"] as? [[String: Any]] else {
            return []
        }

        return data.compactMap { model in
            (model["id"] as? String)?.nilIfEmpty
        }
    }

    static func threadID(from message: [String: Any]) -> String? {
        guard let result = message["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any] else {
            return nil
        }
        return thread["id"] as? String
    }

    static func turnID(from message: [String: Any]) -> String? {
        guard let result = message["result"] as? [String: Any],
              let turn = result["turn"] as? [String: Any] else {
            return nil
        }
        return turn["id"] as? String
    }

    static func agentMessageDelta(from message: [String: Any], threadID: String?, turnID: String?) -> String? {
        guard message["method"] as? String == "item/agentMessage/delta",
              let params = message["params"] as? [String: Any],
              matches(params: params, threadID: threadID, turnID: turnID) else {
            return nil
        }
        return (params["delta"] as? String)?.nilIfEmpty
    }

    static func completedAgentMessage(from message: [String: Any], threadID: String?, turnID: String?) -> String? {
        guard message["method"] as? String == "item/completed",
              let params = message["params"] as? [String: Any],
              matches(params: params, threadID: threadID, turnID: turnID),
              let item = params["item"] as? [String: Any],
              item["type"] as? String == "agentMessage" else {
            return nil
        }
        return (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func isTurnCompleted(_ message: [String: Any], threadID: String?, turnID: String?) throws -> Bool {
        guard message["method"] as? String == "turn/completed",
              let params = message["params"] as? [String: Any],
              matches(params: params, threadID: threadID, turnID: nil),
              let turn = params["turn"] as? [String: Any],
              turnID == nil || turn["id"] as? String == turnID else {
            return false
        }

        switch turn["status"] as? String {
        case "completed":
            return true
        case "failed", "interrupted":
            let error = turn["error"] as? [String: Any]
            throw AIExplanationError.server(
                (error?["message"] as? String)?.nilIfEmpty ?? AppUILanguage.saved().text(.codexRequestIncomplete)
            )
        default:
            throw AIExplanationError.transport(AppUILanguage.saved().text(.codexInvalidCompletionStatus))
        }
    }

    private static func matches(params: [String: Any], threadID: String?, turnID: String?) -> Bool {
        if let threadID, params["threadId"] as? String != threadID {
            return false
        }
        if let turnID, params["turnId"] as? String != turnID {
            return false
        }
        return true
    }
}

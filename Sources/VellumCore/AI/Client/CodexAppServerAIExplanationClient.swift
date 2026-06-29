import Foundation

struct CodexAppServerAIExplanationClient: AIExplaining {
    func testConnection(configuration: AIConfiguration) async throws -> String {
        let models = try await fetchModels(configuration: configuration)
        return models.isEmpty
            ? "Codex App Server is available. No models returned."
            : "Codex App Server available. \(models.count) models available."
    }

    func testFunction(configuration: AIConfiguration) async throws -> String {
        let text = try await runTurn(
            prompt: "Reply with OK.",
            configuration: configuration,
            timeout: 90,
            onChunk: nil
        )
        return text.isEmpty ? "Codex App Server responded." : "Codex App Server responded: \(text)"
    }

    func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        try await withAppServerSession(configuration: configuration, timeout: 45) { session in
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
    }

    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        try await runTurn(
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
            prompt: explanationPrompt(for: context),
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
        prompt: String,
        configuration: AIConfiguration,
        timeout: TimeInterval,
        onChunk: (@MainActor (String) -> Void)?
    ) async throws -> String {
        try await withAppServerSession(configuration: configuration, timeout: timeout) { session in
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
                        throw AIExplanationError.transport("Codex App Server 没有返回 thread id。")
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

                if CodexAppServerMessageParser.isTurnCompleted(message, threadID: threadID, turnID: turnID) {
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
        """
        你是 Vellum 的阅读助手。你必须基于用户提供的原文和上下文回答，重点解释用户选中文本本身，不要默认总结整段。若选中文本是单个英文单词或常见英文词形，附上音标；若选中文本本来是中文或无需翻译，省略中文翻译部分。

        \(context.prompt)
        """
    }

    private func withAppServerSession<T: Sendable>(
        configuration: AIConfiguration,
        timeout: TimeInterval,
        operation: @escaping @Sendable (CodexAppServerSession) async throws -> T
    ) async throws -> T {
        let session = try CodexAppServerSession(configuration: configuration)
        defer {
            session.stop()
        }

        return try await withTimeout(timeout) {
            try await operation(session)
        }
    }

    private func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AIExplanationError.transport("Codex App Server 请求超时。")
            }

            guard let result = try await group.next() else {
                throw AIExplanationError.transport("Codex App Server 请求未完成。")
            }
            group.cancelAll()
            return result
        }
    }
}

private final class CodexAppServerSession: @unchecked Sendable {
    private let process: Process
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrTask: Task<String, Never>
    private let stdinLock = NSLock()

    init(configuration: AIConfiguration) throws {
        let executablePath = configuration.codexExecutablePath
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw AIExplanationError.transport("Codex App Server 不可执行：\(executablePath)")
        }

        process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = Self.arguments(configuration: configuration)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stderrTask = Task.detached { [stderrPipe] in
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }

        do {
            try process.run()
        } catch {
            throw AIExplanationError.transport("Codex App Server 启动失败：\(error.localizedDescription)")
        }
    }

    func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)

        stdinLock.lock()
        defer { stdinLock.unlock() }
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data("\n".utf8))
    }

    func readMessages(until shouldStop: ([String: Any]) async throws -> Bool) async throws {
        for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
            guard let message = CodexAppServerMessageParser.message(from: line) else { continue }
            if try await shouldStop(message) {
                return
            }
        }

        let stderr = await stderrTask.value
        throw AIExplanationError.transport(
            stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Codex App Server 连接已关闭。"
        )
    }

    func stop() {
        try? stdinPipe.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
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
        guard let error = message["error"] as? [String: Any] else { return nil }
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

    static func isTurnCompleted(_ message: [String: Any], threadID: String?, turnID: String?) -> Bool {
        guard message["method"] as? String == "turn/completed",
              let params = message["params"] as? [String: Any],
              matches(params: params, threadID: threadID, turnID: nil) else {
            return false
        }

        guard let turnID,
              let turn = params["turn"] as? [String: Any] else {
            return true
        }

        return turn["id"] as? String == turnID
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

import Foundation

struct CodexCLIAIExplanationClient: AIExplaining {
    func testConnection(configuration: AIConfiguration) async throws -> String {
        let output = try await CodexCLIProcess.run(
            executablePath: configuration.codexExecutablePath,
            arguments: ["--version"],
            stdin: nil,
            timeout: 15
        )
        let version = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "Codex CLI is available." : "Codex CLI available: \(version)"
    }

    func testFunction(configuration: AIConfiguration) async throws -> String {
        let text = try await runCodex(
            prompt: "Reply with OK.",
            configuration: configuration,
            timeout: 90
        )
        return text.isEmpty ? "Codex CLI responded." : "Codex CLI responded: \(text)"
    }

    func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        []
    }

    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        try await runCodex(
            prompt: explanationPrompt(for: context),
            configuration: configuration,
            timeout: 180
        )
    }

    func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let explanation = try await explain(context: context, configuration: configuration)
        await MainActor.run {
            onChunk(explanation)
        }
        return explanation
    }

    private func runCodex(
        prompt: String,
        configuration: AIConfiguration,
        timeout: TimeInterval
    ) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vellum-codex-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        var arguments = [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--color", "never",
            "--output-last-message", outputURL.path
        ]

        if !configuration.model.isEmpty {
            arguments.append(contentsOf: ["--model", configuration.model])
        }
        if !configuration.codexProfile.isEmpty {
            arguments.append(contentsOf: ["--profile", configuration.codexProfile])
        }

        arguments.append("-")

        let output = try await CodexCLIProcess.run(
            executablePath: configuration.codexExecutablePath,
            arguments: arguments,
            stdin: prompt,
            timeout: timeout
        )

        let fileText = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutText = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = fileText?.nilIfEmpty ?? stdoutText

        guard !text.isEmpty else {
            throw AIExplanationError.emptyResponse
        }
        return text
    }

    private func explanationPrompt(for context: AIExplanationContext) -> String {
        """
        你是 Vellum 的阅读助手。你必须基于用户提供的原文和上下文回答，重点解释用户选中文本本身，不要默认总结整段。若选中文本是单个英文单词或常见英文词形，附上音标；若选中文本本来是中文或无需翻译，省略中文翻译部分。

        \(context.prompt)
        """
    }
}

private enum CodexCLIProcess {
    struct Output {
        var stdout: String
        var stderr: String
    }

    static func run(
        executablePath: String,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) async throws -> Output {
        try await Task.detached(priority: .userInitiated) {
            try runSynchronously(
                executablePath: executablePath,
                arguments: arguments,
                stdin: stdin,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        executablePath: String,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw AIExplanationError.transport("Codex CLI 不可执行：\(executablePath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vellum-codex-stdout-\(UUID().uuidString).txt")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vellum-codex-stderr-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
              let stderrHandle = try? FileHandle(forWritingTo: stderrURL) else {
            throw AIExplanationError.transport("Codex CLI 临时输出文件创建失败。")
        }
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdinPipe = Pipe()
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw AIExplanationError.transport("Codex CLI 启动失败：\(error.localizedDescription)")
        }

        if let stdin {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try? stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw AIExplanationError.transport("Codex CLI 请求超时。")
        }

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Codex CLI 退出码 \(process.terminationStatus)。"
            throw AIExplanationError.server(message)
        }

        return Output(stdout: stdout, stderr: stderr)
    }
}

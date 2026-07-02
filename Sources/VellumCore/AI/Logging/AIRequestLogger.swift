@preconcurrency import AppKit
import Foundation

struct AIRequestLogEntry: Codable, Equatable {
    var timestamp: Date
    var operation: String
    var provider: String
    var model: String
    var method: String?
    var url: String?
    var statusCode: Int?
    var durationMs: Int
    var requestHeaders: [String: String]
    var requestBody: String?
    var responseBody: String?
    var error: String?
}

enum AIRequestLogger {
    private static let lock = NSLock()
    private static let maxRequestBodyCharacters = 20_000
    private static let maxResponseBodyCharacters = 12_000

    static var logFileURL: URL {
        logsDirectoryURL.appendingPathComponent("ai-requests.jsonl")
    }

    static func recordHTTP(
        operation: String,
        configuration: AIConfiguration,
        request: URLRequest,
        response: URLResponse?,
        startedAt: Date,
        responseData: Data? = nil,
        responseText: String? = nil,
        error: Error? = nil
    ) {
        let entry = AIRequestLogEntry(
            timestamp: Date(),
            operation: operation,
            provider: configuration.providerFormat.title,
            model: configuration.model,
            method: request.httpMethod,
            url: request.url?.absoluteString,
            statusCode: (response as? HTTPURLResponse)?.statusCode,
            durationMs: durationMs(since: startedAt),
            requestHeaders: sanitizedHeaders(request.allHTTPHeaderFields),
            requestBody: textPreview(from: request.httpBody, maxCharacters: maxRequestBodyCharacters),
            responseBody: responseText?.limitedForLog(maxResponseBodyCharacters)
                ?? textPreview(from: responseData, maxCharacters: maxResponseBodyCharacters),
            error: error.map { String(describing: $0).limitedForLog(maxResponseBodyCharacters) }
        )
        append(entry)
    }

    static func recordLocal(
        operation: String,
        configuration: AIConfiguration,
        prompt: String? = nil,
        responseText: String? = nil,
        startedAt: Date,
        error: Error? = nil
    ) {
        let entry = AIRequestLogEntry(
            timestamp: Date(),
            operation: operation,
            provider: configuration.providerFormat.title,
            model: configuration.model.nilIfEmpty ?? "Default",
            method: "LOCAL",
            url: configuration.codexExecutablePath,
            statusCode: nil,
            durationMs: durationMs(since: startedAt),
            requestHeaders: [:],
            requestBody: prompt?.limitedForLog(maxRequestBodyCharacters),
            responseBody: responseText?.limitedForLog(maxResponseBodyCharacters),
            error: error.map { String(describing: $0).limitedForLog(maxResponseBodyCharacters) }
        )
        append(entry)
    }

    @discardableResult
    static func ensureLogFileExists() throws -> URL {
        let fileURL = logFileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL, options: .atomic)
        }
        return fileURL
    }

    static func openLog() throws {
        let fileURL = try ensureLogFileExists()
        NSWorkspace.shared.open(fileURL)
    }

    static func clearLog() throws {
        let fileURL = try ensureLogFileExists()
        try Data().write(to: fileURL, options: .atomic)
    }

    static func sanitizedHeaders(_ headers: [String: String]?) -> [String: String] {
        guard let headers else { return [:] }
        let sensitiveNames = Set(["authorization", "x-api-key", "api-key", "cookie"])
        return headers.reduce(into: [:]) { result, pair in
            if sensitiveNames.contains(pair.key.lowercased()) {
                result[pair.key] = "<redacted>"
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    static func textPreview(from data: Data?, maxCharacters: Int) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let pretty = prettyPrintedJSON(from: data) {
            return pretty.limitedForLog(maxCharacters)
        }
        return String(data: data, encoding: .utf8)?.limitedForLog(maxCharacters)
    }

    private static var logsDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["VELLUM_AI_LOG_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override)
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return appSupport
            .appendingPathComponent("Vellum", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private static func append(_ entry: AIRequestLogEntry) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let fileURL = try ensureLogFileExists()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(entry)
            data.append(0x0A)

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("Vellum AI request logging failed: \(error.localizedDescription)")
        }
    }

    private static func durationMs(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private static func prettyPrintedJSON(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }
}

private extension String {
    func limitedForLog(_ limit: Int) -> String {
        guard count > limit else { return self }
        return "\(prefix(limit))\n... <truncated \(count - limit) characters>"
    }
}

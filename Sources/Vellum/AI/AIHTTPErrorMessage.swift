import Foundation

enum AIHTTPErrorMessage {
    static func message(from data: Data, statusCode: Int) -> String {
        let fallback = "AI 请求失败，HTTP \(statusCode)。"
        guard let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty else {
            return fallback
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "AI 请求失败，HTTP \(statusCode)：\(rawMessage)"
        }

        if let error = json["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.nilIfEmpty
            let type = (error["type"] as? String)?.nilIfEmpty
            let code = (error["code"] as? String)?.nilIfEmpty
            let param = (error["param"] as? String)?.nilIfEmpty
            let details = [
                type.map { "type=\($0)" },
                code.map { "code=\($0)" },
                param.map { "param=\($0)" }
            ].compactMap { $0 }.joined(separator: ", ")
            if let message, !details.isEmpty {
                return "AI 请求失败，HTTP \(statusCode)：\(message)（\(details)）"
            }
            if let message {
                return "AI 请求失败，HTTP \(statusCode)：\(message)"
            }
        }

        if let message = (json["message"] as? String)?.nilIfEmpty {
            return "AI 请求失败，HTTP \(statusCode)：\(message)"
        }

        return "AI 请求失败，HTTP \(statusCode)：\(rawMessage)"
    }
}

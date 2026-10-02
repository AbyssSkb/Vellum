import Foundation

enum AIHTTPErrorMessage {
    static func message(from data: Data, statusCode: Int?, language: AppUILanguage = .saved()) -> String {
        func formatted(_ message: String? = nil, details: String? = nil) -> String {
            language.text(.aiRequestFailed(status: statusCode, message: message, details: details))
        }
        guard let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty else {
            return formatted()
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return formatted(rawMessage)
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
                return formatted(message, details: details)
            }
            if let message {
                return formatted(message)
            }
        }

        if let message = (json["message"] as? String)?.nilIfEmpty {
            return formatted(message)
        }

        return formatted(rawMessage)
    }
}

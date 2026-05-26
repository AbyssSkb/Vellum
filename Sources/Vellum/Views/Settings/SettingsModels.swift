@preconcurrency import AppKit

enum SettingsCategory: String, CaseIterable, Identifiable {
    case ai
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai:
            return "AI"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .ai:
            return "Provider and model"
        case .shortcuts:
            return "Keyboard map"
        }
    }

    var systemImage: String {
        switch self {
        case .ai:
            return "sparkles"
        case .shortcuts:
            return "keyboard"
        }
    }
}

enum AIConnectionStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .idle:
            return "Not checked"
        case .working(let message), .success(let message), .failure(let message):
            return message
        }
    }

    var color: NSColor {
        switch self {
        case .idle:
            return TokyoNight.muted
        case .working:
            return TokyoNight.blue
        case .success:
            return NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.49, alpha: 1)
        case .failure:
            return TokyoNight.red
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

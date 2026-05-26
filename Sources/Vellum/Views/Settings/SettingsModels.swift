@preconcurrency import AppKit
import SwiftUI

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

    var systemImage: String {
        switch self {
        case .idle:
            return "circle"
        case .working:
            return "clock"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .working:
            return .accentColor
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

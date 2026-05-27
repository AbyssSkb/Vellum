@preconcurrency import AppKit
import SwiftUI

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case cyan
    case purple
    case pink

    var id: String { rawValue }

    var swatchColor: Color {
        Color(nsColor: displayColor)
    }

    var displayColor: NSColor {
        switch self {
        case .yellow:
            return NSColor(calibratedRed: 0.88, green: 0.74, blue: 0.35, alpha: 1)
        case .green:
            return NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.49, alpha: 1)
        case .cyan:
            return TokyoNight.cyan
        case .purple:
            return TokyoNight.purple
        case .pink:
            return TokyoNight.red
        }
    }

    var annotationColor: NSColor {
        displayColor.persistentHighlightColor()
    }

    var next: HighlightColor {
        let colors = Self.allCases
        guard let index = colors.firstIndex(of: self) else { return .yellow }
        return colors[(index + 1) % colors.count]
    }

    var helpText: String {
        switch self {
        case .yellow:
            return "Yellow highlight"
        case .green:
            return "Green highlight"
        case .cyan:
            return "Cyan highlight"
        case .purple:
            return "Purple highlight"
        case .pink:
            return "Pink highlight"
        }
    }
}

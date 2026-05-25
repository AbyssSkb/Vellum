@preconcurrency import AppKit
import PDFKit
import SwiftUI

struct PDFTab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var document: PDFDocument?
    var snapshot: ReaderSnapshot?

    var title: String {
        url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    init(id: UUID = UUID(), url: URL?, document: PDFDocument?, snapshot: ReaderSnapshot? = nil) {
        self.id = id
        self.url = url
        self.document = document
        self.snapshot = snapshot
    }
}

struct ReaderSnapshot: Equatable {
    static let initial = ReaderSnapshot(
        pageIndex: 0,
        pointOnPage: .zero,
        scrollOrigin: nil,
        scaleFactor: 0,
        autoScales: true
    )

    var pageIndex: Int
    var pointOnPage: NSPoint
    var scrollOrigin: NSPoint?
    var scaleFactor: CGFloat
    var autoScales: Bool
}

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

enum PDFOpenMode {
    case currentTab
    case newTabs
}

enum VimCommand {
    case open
    case openInNewTab
    case closeTab
    case restoreClosedTab
    case nextTab
    case previousTab
    case scrollDown
    case scrollUp
    case largeScrollDown
    case largeScrollUp
    case scrollLeft
    case scrollRight
    case pageDown
    case pageUp
    case firstPage
    case lastPage
    case jumpToPage(Int)
    case jumpBack
    case jumpForward
    case toggleOutline
    case highlightSelection
    case cycleHighlightColor
    case explainHighlightSelection
    case zoomIn
    case zoomOut
    case zoomPageFit
    case zoomFit
}

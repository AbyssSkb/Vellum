@preconcurrency import AppKit

enum SearchReadingAnchor {
    static let viewportRatio: CGFloat = 0.30

    static func pointY(visibleMinY: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        visibleMinY + visibleHeight * viewportRatio
    }
}

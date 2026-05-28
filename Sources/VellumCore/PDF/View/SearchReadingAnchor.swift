@preconcurrency import AppKit

enum SearchReadingAnchor {
    static let viewportRatio: CGFloat = 0.30

    static func pointY(visibleMinY: CGFloat, visibleHeight: CGFloat, isFlipped: Bool) -> CGFloat {
        if isFlipped {
            return visibleMinY + visibleHeight * viewportRatio
        }

        return visibleMinY + visibleHeight * (1 - viewportRatio)
    }
}

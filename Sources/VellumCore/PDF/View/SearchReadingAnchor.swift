@preconcurrency import AppKit

enum SearchReadingAnchor {
    static func pointY(visibleMinY: CGFloat, visibleHeight: CGFloat, isFlipped: Bool) -> CGFloat {
        if isFlipped {
            return visibleMinY
        }

        return visibleMinY + visibleHeight
    }
}

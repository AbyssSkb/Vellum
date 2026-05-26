@preconcurrency import AppKit

enum AIExplanationGeometry {
    static func groupBounds(for regions: [NSRect], fallbackBounds: NSRect? = nil) -> NSRect? {
        if let regionBounds = HighlightGeometry.rect(containing: cornerPoints(for: regions)) {
            return regionBounds
        }

        guard let fallbackBounds else { return nil }
        return HighlightGeometry.rect(containing: cornerPoints(for: [fallbackBounds]))
    }

    static func hoverContains(_ point: NSPoint, in groupBounds: NSRect) -> Bool {
        groupBounds.insetBy(dx: -5, dy: -8).contains(point)
    }

    static func popoverAnchorRect(from viewRect: NSRect) -> NSRect {
        viewRect.insetBy(dx: -3, dy: -3)
    }

    static func fallbackAnchorRect(at point: NSPoint) -> NSRect {
        NSRect(x: point.x, y: point.y, width: 1, height: 1)
    }

    private static func cornerPoints(for rects: [NSRect]) -> [NSPoint] {
        rects.flatMap { rect in
            [
                NSPoint(x: rect.minX, y: rect.minY),
                NSPoint(x: rect.maxX, y: rect.minY),
                NSPoint(x: rect.minX, y: rect.maxY),
                NSPoint(x: rect.maxX, y: rect.maxY)
            ]
        }
    }
}

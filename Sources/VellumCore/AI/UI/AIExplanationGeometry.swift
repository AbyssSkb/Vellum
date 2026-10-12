@preconcurrency import AppKit

enum AIExplanationGeometry {
    static func groupBounds(for regions: [NSRect]) -> NSRect? {
        HighlightGeometry.rect(containing: cornerPoints(for: regions))
    }

    static func hoverContains(_ point: NSPoint, in groupBounds: NSRect) -> Bool {
        groupBounds.insetBy(dx: -5, dy: -8).contains(point)
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

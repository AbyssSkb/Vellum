@preconcurrency import AppKit

enum ScrollGeometry {
    enum VerticalEdge {
        case top
        case bottom
    }

    static func nextCoordinate(
        origin: CGFloat,
        delta: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard delta != 0 else { return origin }
        guard contentLength > viewportLength else { return origin }
        return clamped(origin + delta, maxValue: maxValue)
    }

    static func restoredCoordinate(
        origin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return origin }
        return clamped(origin, maxValue: maxValue)
    }

    static func centeredCoordinate(
        point: CGFloat,
        currentOrigin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return currentOrigin }
        return clamped(point - viewportLength / 2, maxValue: maxValue)
    }

    static func verticalEdgeCoordinate(edge: VerticalEdge, isFlipped: Bool, maxValue: CGFloat) -> CGFloat {
        switch (edge, isFlipped) {
        case (.top, true), (.bottom, false):
            return 0
        case (.top, false), (.bottom, true):
            return maxValue
        }
    }

    static func comfortableVisibleOrigin(
        currentOrigin: NSPoint,
        visibleSize: NSSize,
        documentBounds: NSRect,
        targetRect: NSRect
    ) -> NSPoint? {
        let visibleRect = NSRect(origin: currentOrigin, size: visibleSize)
        let marginX = min(44, visibleRect.width * 0.12)
        let marginY = min(56, visibleRect.height * 0.14)
        let comfortableRect = visibleRect.insetBy(dx: marginX, dy: marginY)

        guard !comfortableRect.contains(targetRect) else { return nil }

        let maxOriginX = max(documentBounds.minX, documentBounds.maxX - visibleRect.width)
        let maxOriginY = max(documentBounds.minY, documentBounds.maxY - visibleRect.height)
        var nextOrigin = visibleRect.origin

        if targetRect.minX < comfortableRect.minX {
            nextOrigin.x += targetRect.minX - comfortableRect.minX
        } else if targetRect.maxX > comfortableRect.maxX {
            nextOrigin.x += targetRect.maxX - comfortableRect.maxX
        }

        if targetRect.minY < comfortableRect.minY {
            nextOrigin.y += targetRect.minY - comfortableRect.minY
        } else if targetRect.maxY > comfortableRect.maxY {
            nextOrigin.y += targetRect.maxY - comfortableRect.maxY
        }

        nextOrigin.x = min(max(documentBounds.minX, nextOrigin.x), maxOriginX)
        nextOrigin.y = min(max(documentBounds.minY, nextOrigin.y), maxOriginY)

        guard abs(nextOrigin.x - visibleRect.origin.x) > 0.5
            || abs(nextOrigin.y - visibleRect.origin.y) > 0.5 else { return nil }

        return nextOrigin
    }

    private static func clamped(_ value: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(0, value), maxValue)
    }
}

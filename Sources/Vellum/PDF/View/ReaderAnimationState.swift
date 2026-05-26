@preconcurrency import AppKit
import PDFKit

@MainActor
final class ReaderAnimationState {
    var scrollTargetOrigin: NSPoint?
    var scrollTimer: Timer?
    var lastScrollTick = Date.timeIntervalSinceReferenceDate
    var zoomTargetScale: CGFloat?
    var zoomAnchor: PDFDestination?
    var zoomTimer: Timer?
    var lastZoomTick = Date.timeIntervalSinceReferenceDate

    var hasActiveScrollTimer: Bool {
        scrollTimer?.isValid == true
    }

    var hasActiveZoomTimer: Bool {
        zoomTimer?.isValid == true
    }

    func clearScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollTargetOrigin = nil
    }

    func clearZoom() {
        zoomTimer?.invalidate()
        zoomTimer = nil
        zoomTargetScale = nil
        zoomAnchor = nil
    }
}

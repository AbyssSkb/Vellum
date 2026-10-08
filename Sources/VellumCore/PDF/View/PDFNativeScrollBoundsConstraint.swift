@preconcurrency import AppKit
import ObjectiveC.runtime

@MainActor
enum PDFNativeScrollBoundsConstraint {
    private static var contextKey: UInt8 = 0

    @MainActor private final class Context {
        weak var pdfView: VellumPDFView?
        weak var clipView: NSClipView?
        var range: ClosedRange<CGFloat>?
        var viewportSize = NSSize.zero
        var scaleFactor: CGFloat = 0
        var phaseActive = false
        var liveScrollActive = false
        var settleWorkItem: DispatchWorkItem?
        var generation = 0

        func cancelSettle() {
            settleWorkItem?.cancel()
            settleWorkItem = nil
            generation += 1
        }

        func clear() {
            cancelSettle()
            range = nil
            phaseActive = false
            liveScrollActive = false
        }
    }

    static func install(on scrollView: NSScrollView, for pdfView: VellumPDFView) {
        let context = context(for: scrollView) ?? Context()
        if context.pdfView !== pdfView || context.clipView !== scrollView.contentView {
            context.clear()
        }
        context.pdfView = pdfView
        context.clipView = scrollView.contentView
        objc_setAssociatedObject(scrollView, &contextKey, context, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func withNativeScroll(on scrollView: NSScrollView, event: NSEvent, operation: () -> Void) {
        guard let context = prepare(in: scrollView) else {
            operation()
            return
        }
        let phase = event.momentumPhase.isEmpty ? event.phase : event.momentumPhase
        context.phaseActive = !phase.isEmpty && phase.intersection([.ended, .cancelled]).isEmpty
        operation()
        scheduleSettle(in: scrollView)
    }

    static func beginLiveScroll(in scrollView: NSScrollView) {
        prepare(in: scrollView)?.liveScrollActive = true
    }

    static func endLiveScroll(in scrollView: NSScrollView) {
        context(for: scrollView)?.liveScrollActive = false
        scheduleSettle(in: scrollView)
    }

    static func boundsDidChange(in scrollView: NSScrollView) {
        guard let context = context(for: scrollView), context.range != nil else { return }
        guard isValid(context, in: scrollView) else {
            context.clear()
            return
        }
        scheduleSettle(in: scrollView)
    }

    static func cancel(in scrollView: NSScrollView) {
        context(for: scrollView)?.clear()
    }

    private static func context(for scrollView: NSScrollView) -> Context? {
        objc_getAssociatedObject(scrollView, &contextKey) as? Context
    }

    private static func prepare(in scrollView: NSScrollView) -> Context? {
        guard let context = context(for: scrollView), let pdfView = context.pdfView,
              pdfView.window?.inLiveResize != true,
              pdfView.pendingRestoreAction == nil,
              pdfView.animationState.scrollTargetOrigin == nil,
              pdfView.animationState.zoomTargetScale == nil else { return nil }
        if context.range != nil, !isValid(context, in: scrollView) { context.clear() }
        context.cancelSettle()
        if context.range == nil {
            context.clipView = scrollView.contentView
            context.viewportSize = scrollView.contentView.bounds.size
            context.scaleFactor = pdfView.scaleFactor
            context.range = pdfView.verticalScrollRange(in: scrollView)
        }
        return context
    }

    private static func isValid(_ context: Context, in scrollView: NSScrollView) -> Bool {
        guard let pdfView = context.pdfView else { return false }
        return context.clipView === scrollView.contentView
            && ZoomGeometry.isSameViewportSize(context.viewportSize, scrollView.contentView.bounds.size)
            && context.scaleFactor == pdfView.scaleFactor
            && pdfView.window != nil && pdfView.window?.inLiveResize != true
            && pdfView.pendingRestoreAction == nil
            && pdfView.animationState.scrollTargetOrigin == nil
            && pdfView.animationState.zoomTargetScale == nil
    }

    private static func scheduleSettle(in scrollView: NSScrollView) {
        guard let context = context(for: scrollView), let range = context.range else { return }
        context.cancelSettle()
        guard !context.phaseActive, !context.liveScrollActive else { return }
        let generation = context.generation
        let workItem = DispatchWorkItem { [weak context, weak scrollView] in
            MainActor.assumeIsolated {
                guard let context, let scrollView, context.generation == generation else { return }
                guard isValid(context, in: scrollView) else {
                    context.clear()
                    return
                }
                context.clear()
                let clipView = scrollView.contentView
                let origin = clipView.bounds.origin
                let y = min(max(origin.y, range.lowerBound), range.upperBound)
                guard abs(origin.y - y) > 0.001 else { return }
                clipView.scroll(to: NSPoint(x: origin.x, y: y))
                scrollView.reflectScrolledClipView(clipView)
            }
        }
        context.settleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}

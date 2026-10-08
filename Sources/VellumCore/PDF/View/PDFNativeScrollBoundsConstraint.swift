@preconcurrency import AppKit
import ObjectiveC.runtime

@MainActor
enum PDFNativeScrollBoundsConstraint {
    private static let constrainedClassPrefix = "VellumNativeScrollBoundsConstrained_"
    private static var contextKey: UInt8 = 0

    private final class Context {
        weak var pdfView: VellumPDFView?
        var activeRange: ClosedRange<CGFloat>?

        init(pdfView: VellumPDFView) {
            self.pdfView = pdfView
        }
    }

    static func install(on scrollView: NSScrollView, for pdfView: VellumPDFView) {
        let context = context(for: scrollView) ?? Context(pdfView: pdfView)
        context.pdfView = pdfView
        let clipView = scrollView.contentView
        objc_setAssociatedObject(scrollView, &contextKey, context, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(clipView, &contextKey, context, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        guard let currentClass = object_getClass(clipView),
              !NSStringFromClass(currentClass).hasPrefix(constrainedClassPrefix),
              let constrainedClass = constrainedSubclass(for: currentClass) else { return }
        object_setClass(clipView, constrainedClass)
    }

    static func withNativeScroll(on scrollView: NSScrollView, operation: () -> Void) {
        guard let context = context(for: scrollView), let pdfView = context.pdfView else {
            operation()
            return
        }
        let previousRange = context.activeRange
        context.activeRange = pdfView.verticalScrollRange(in: scrollView)
        defer { context.activeRange = previousRange }
        operation()
    }

    static func nativeDragRange(in clipView: NSClipView, event: NSEvent?) -> ClosedRange<CGFloat>? {
        guard let event, event.type == .leftMouseDragged,
              let pdfView = context(for: clipView)?.pdfView,
              let scrollView = clipView.enclosingScrollView,
              event.window === scrollView.window,
              scrollView.verticalScroller?.hitPart == .knob,
              pdfView.window?.inLiveResize != true,
              pdfView.pendingRestoreAction == nil,
              pdfView.animationState.scrollTargetOrigin == nil,
              pdfView.animationState.zoomTargetScale == nil else { return nil }
        return pdfView.verticalScrollRange(in: scrollView)
    }

    private static func context(for object: AnyObject) -> Context? {
        objc_getAssociatedObject(object, &contextKey) as? Context
    }

    private static func constrainedSubclass(for originalClass: AnyClass) -> AnyClass? {
        let originalName = NSStringFromClass(originalClass).map { character in
            character.isLetter || character.isNumber || character == "_" ? character : "_"
        }
        let subclassName = constrainedClassPrefix + String(originalName)
        if let existingClass = NSClassFromString(subclassName) { return existingClass }
        guard let subclass = objc_allocateClassPair(originalClass, subclassName, 0) else {
            return NSClassFromString(subclassName)
        }

        let selector = #selector(NSClipView.constrainBoundsRect(_:))
        guard let method = class_getInstanceMethod(originalClass, selector) else {
            objc_disposeClassPair(subclass)
            return nil
        }
        typealias ConstrainBounds = @convention(c) (AnyObject, Selector, NSRect) -> NSRect
        let originalConstrainBounds = unsafeBitCast(method_getImplementation(method), to: ConstrainBounds.self)
        let constrainedBounds: @convention(block) (NSClipView, NSRect) -> NSRect = { clipView, proposed in
            var result = originalConstrainBounds(clipView, selector, proposed)
            return MainActor.assumeIsolated {
                if let range = context(for: clipView)?.activeRange
                    ?? nativeDragRange(in: clipView, event: NSApp?.currentEvent) {
                    result.origin.y = min(max(result.origin.y, range.lowerBound), range.upperBound)
                }
                return result
            }
        }
        guard class_addMethod(
            subclass,
            selector,
            imp_implementationWithBlock(constrainedBounds),
            method_getTypeEncoding(method)
        ) else {
            objc_disposeClassPair(subclass)
            return nil
        }
        objc_registerClassPair(subclass)
        return subclass
    }
}

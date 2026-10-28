@preconcurrency import AppKit
import ObjectiveC.runtime

@MainActor
enum PDFOverlayScrollerStyleLock {
    private static var enabledKey: UInt8 = 0
    private static var hookedClasses: Set<ObjectIdentifier> = []

    static func install(on scrollView: NSScrollView) {
        // Preserve AppKit's dynamic-property and KVO classes during teardown.
        guard installHooks(on: scrollView.classForCoder) else {
            scrollView.scrollerStyle = .overlay
            return
        }

        objc_setAssociatedObject(scrollView, &enabledKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        scrollView.scrollerStyle = .overlay
    }

    private static func installHooks(on originalClass: AnyClass) -> Bool {
        let classID = ObjectIdentifier(originalClass)
        if hookedClasses.contains(classID) { return true }
        let selector = #selector(setter: NSScrollView.scrollerStyle)
        let wheelSelector = #selector(NSScrollView.scrollWheel(with:))
        guard let method = class_getInstanceMethod(originalClass, selector),
              let wheelMethod = class_getInstanceMethod(originalClass, wheelSelector) else { return false }

        let originalImplementation = method_getImplementation(method)
        typealias Setter = @convention(c) (AnyObject, Selector, NSScroller.Style) -> Void
        let originalSetter = unsafeBitCast(originalImplementation, to: Setter.self)
        let lockedSetter: @convention(block) @MainActor (NSScrollView, NSScroller.Style) -> Void = { scrollView, style in
            let isEnabled = objc_getAssociatedObject(scrollView, &enabledKey) != nil
            originalSetter(scrollView, selector, isEnabled && style == .legacy ? .overlay : style)
        }

        typealias ScrollWheel = @convention(c) @Sendable (AnyObject, Selector, NSEvent) -> Void
        let originalScrollWheel = unsafeBitCast(method_getImplementation(wheelMethod), to: ScrollWheel.self)
        let constrainedScrollWheel: @convention(block) @MainActor (NSScrollView, NSEvent) -> Void = { scrollView, event in
            guard objc_getAssociatedObject(scrollView, &enabledKey) != nil else {
                originalScrollWheel(scrollView, wheelSelector, event)
                return
            }
            var scrollingEvent = event
            if event.hasPreciseScrollingDeltas, event.phase.contains(.began),
               event.scrollingDeltaY != 0, event.scrollingDeltaX != 0, abs(event.scrollingDeltaX) < 4,
               event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
               let cgEvent = event.cgEvent?.copy() {
                // Keep a small diagonal start from latching native scrolling to finger drift.
                cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
                cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
                cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
                cgEvent.setDoubleValueField(.scrollWheelEventRawDeltaAxis2, value: 0)
                cgEvent.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis2, value: 0)
                scrollingEvent = NSEvent(cgEvent: cgEvent) ?? event
            }
            PDFNativeScrollBoundsConstraint.withNativeScroll(on: scrollView, event: scrollingEvent) {
                originalScrollWheel(scrollView, wheelSelector, scrollingEvent)
            }
        }
        class_replaceMethod(
            originalClass,
            selector,
            imp_implementationWithBlock(lockedSetter),
            method_getTypeEncoding(method)
        )
        class_replaceMethod(
            originalClass,
            wheelSelector,
            imp_implementationWithBlock(constrainedScrollWheel),
            method_getTypeEncoding(wheelMethod)
        )
        hookedClasses.insert(classID)
        return true
    }
}

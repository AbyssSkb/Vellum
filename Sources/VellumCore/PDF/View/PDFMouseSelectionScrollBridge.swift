@preconcurrency import AppKit
import ObjectiveC.runtime

@MainActor
enum PDFMouseSelectionScrollBridge {
    private static let bridgedClassPrefix = "VellumMouseSelectionScrollBridged_"
    nonisolated(unsafe) private static var trackingPDFViewKey: UInt8 = 0

    static func beginTracking(_ pdfView: VellumPDFView, in window: NSWindow) {
        install(on: window)
        install(on: NSApp)
        setActiveTrackingPDFView(pdfView, on: window)
        setActiveTrackingPDFView(pdfView, on: NSApp)
    }

    static func endTracking(_ pdfView: VellumPDFView, in window: NSWindow) {
        if activeTrackingPDFView(for: window) === pdfView {
            clearActiveTrackingPDFView(on: window)
        }
        if activeTrackingPDFView(for: NSApp) === pdfView {
            clearActiveTrackingPDFView(on: NSApp)
        }
    }

    private static func install(on object: AnyObject) {
        guard let currentClass = object_getClass(object) else { return }
        guard !NSStringFromClass(currentClass).hasPrefix(bridgedClassPrefix) else { return }
        guard let bridgedClass = bridgedSubclass(for: currentClass) else { return }
        object_setClass(object, bridgedClass)
    }

    private static func bridgedSubclass(for originalClass: AnyClass) -> AnyClass? {
        let subclassName = bridgedSubclassName(for: originalClass)
        if let existingClass = NSClassFromString(subclassName) {
            return existingClass
        }

        guard let subclass = objc_allocateClassPair(originalClass, subclassName, 0) else {
            return NSClassFromString(subclassName)
        }

        let selector = #selector(NSApplication.nextEvent(matching:until:inMode:dequeue:))
        guard let method = class_getInstanceMethod(originalClass, selector) else {
            objc_disposeClassPair(subclass)
            return nil
        }

        let originalImplementation = method_getImplementation(method)
        typealias NextEventImplementation = @convention(c) (
            AnyObject,
            Selector,
            UInt64,
            NSDate?,
            NSString,
            Bool
        ) -> NSEvent?
        let originalNextEvent = unsafeBitCast(originalImplementation, to: NextEventImplementation.self)

        let bridgedNextEvent: @convention(block) (
            AnyObject,
            UInt64,
            NSDate?,
            NSString,
            Bool
        ) -> NSEvent? = { object, mask, untilDate, mode, dequeue in
            let adjustedMask = shouldBridgeNextEvent(
                for: object,
                mask: mask,
                mode: mode,
                dequeue: dequeue
            )
                ? mask | NSEvent.EventTypeMask.scrollWheel.rawValue
                : mask
            let isBridgingScrollWheel = adjustedMask != mask

            while true {
                guard let event = originalNextEvent(object, selector, adjustedMask, untilDate, mode, dequeue) else {
                    return nil
                }

                guard isBridgingScrollWheel, event.type == .scrollWheel else {
                    return event
                }

                if let replacement = replacementEventAfterConsumingScrollWheel(
                    event,
                    eventSource: object,
                    mode: mode,
                    dequeue: dequeue
                ) {
                    return replacement
                }
            }
        }

        guard class_addMethod(
            subclass,
            selector,
            imp_implementationWithBlock(bridgedNextEvent),
            method_getTypeEncoding(method)
        ) else {
            objc_disposeClassPair(subclass)
            return nil
        }

        objc_registerClassPair(subclass)
        return subclass
    }

    private static func bridgedSubclassName(for originalClass: AnyClass) -> String {
        let originalName = NSStringFromClass(originalClass)
        let sanitizedName = originalName.map { character in
            character.isLetter || character.isNumber || character == "_" ? character : "_"
        }

        return bridgedClassPrefix + String(sanitizedName)
    }

    private static func setActiveTrackingPDFView(_ pdfView: VellumPDFView, on object: AnyObject) {
        objc_setAssociatedObject(
            object,
            &trackingPDFViewKey,
            WeakPDFViewBox(pdfView),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private static func clearActiveTrackingPDFView(on object: AnyObject) {
        objc_setAssociatedObject(object, &trackingPDFViewKey, nil, .OBJC_ASSOCIATION_ASSIGN)
    }

    private static func activeTrackingPDFView(for object: AnyObject) -> VellumPDFView? {
        (objc_getAssociatedObject(object, &trackingPDFViewKey) as? WeakPDFViewBox)?.pdfView
    }

    nonisolated private static func shouldBridgeNextEvent(
        for object: AnyObject,
        mask: UInt64,
        mode: NSString,
        dequeue: Bool
    ) -> Bool {
        guard dequeue,
              mode as String == RunLoop.Mode.eventTracking.rawValue else {
            return false
        }

        let requestedEvents = NSEvent.EventTypeMask(rawValue: mask)
        guard requestedEvents.contains(.leftMouseDragged) || requestedEvents.contains(.leftMouseUp) else {
            return false
        }

        let uncheckedObject = UncheckedObject(object)
        return MainActor.assumeIsolated {
            guard let pdfView = activeTrackingPDFView(for: uncheckedObject.object) else { return false }
            return pdfView.shouldBridgeMouseSelectionScrollWheel
        }
    }

    nonisolated private static func replacementEventAfterConsumingScrollWheel(
        _ event: NSEvent,
        eventSource object: AnyObject,
        mode: NSString,
        dequeue: Bool
    ) -> NSEvent? {
        guard dequeue,
              mode as String == RunLoop.Mode.eventTracking.rawValue else {
            return nil
        }

        let uncheckedObject = UncheckedObject(object)
        let uncheckedEvent = UncheckedNSEvent(event)
        let replacement: UncheckedNSEvent? = MainActor.assumeIsolated { () -> UncheckedNSEvent? in
            guard let pdfView = activeTrackingPDFView(for: uncheckedObject.object) else { return nil }
            return pdfView
                .replacementMouseDraggedEventAfterConsumingSelectionScrollWheel(uncheckedEvent.event)
                .map(UncheckedNSEvent.init)
        }
        return replacement?.event
    }
}

private struct UncheckedObject: @unchecked Sendable {
    let object: AnyObject

    init(_ object: AnyObject) {
        self.object = object
    }
}

private struct UncheckedNSEvent: @unchecked Sendable {
    let event: NSEvent

    init(_ event: NSEvent) {
        self.event = event
    }
}

private final class WeakPDFViewBox: NSObject {
    weak var pdfView: VellumPDFView?

    init(_ pdfView: VellumPDFView) {
        self.pdfView = pdfView
        super.init()
    }
}

extension VellumPDFView {
    fileprivate var shouldBridgeMouseSelectionScrollWheel: Bool {
        isMouseSelectingText && (NSEvent.pressedMouseButtons & 1) == 1
    }

    func replacementMouseDraggedEventAfterConsumingSelectionScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard shouldBridgeMouseSelectionScrollWheel,
              let scrollView = pdfScrollView,
              let replacement = mouseDraggedReplacementEvent(for: event) else {
            return nil
        }

        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        searchController?.markReaderNavigated()
        didDragDuringCurrentMouseSequence = true
        pendingClickHorizontalOrigin = nil
        pendingDoubleClickTextSelectionPoint = nil
        didHandleDoubleClickTextSelectionMouseDown = false
        hideAIExplanationPopover()

        let clipView = scrollView.contentView
        let originBeforeScroll = clipView.bounds.origin
        scrollView.scrollWheel(with: event)
        if clipView.bounds.origin != originBeforeScroll {
            scheduleReaderStateSave()
        }

        return replacement
    }

    private func mouseDraggedReplacementEvent(for event: NSEvent) -> NSEvent? {
        guard event.scrollingDeltaX != 0
            || event.scrollingDeltaY != 0
            || event.deltaX != 0
            || event.deltaY != 0 else {
            return nil
        }

        return NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: 1,
            pressure: 0
        )
    }
}

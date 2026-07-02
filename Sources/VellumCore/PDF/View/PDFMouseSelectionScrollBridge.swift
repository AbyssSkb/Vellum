@preconcurrency import AppKit
import ObjectiveC.runtime

@MainActor
enum PDFMouseSelectionScrollBridge {
    private static let bridgedClassPrefix = "VellumMouseSelectionScrollBridged_"
    nonisolated(unsafe) private static var trackingPDFViewKey: UInt8 = 0

    static func beginTracking(_ pdfView: VellumPDFView, in window: NSWindow) {
        install(on: window)
        objc_setAssociatedObject(
            window,
            &trackingPDFViewKey,
            WeakPDFViewBox(pdfView),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func endTracking(_ pdfView: VellumPDFView, in window: NSWindow) {
        guard activeTrackingPDFView(for: window) === pdfView else { return }
        objc_setAssociatedObject(window, &trackingPDFViewKey, nil, .OBJC_ASSOCIATION_ASSIGN)
    }

    private static func install(on window: NSWindow) {
        guard let currentClass = object_getClass(window) else { return }
        guard !NSStringFromClass(currentClass).hasPrefix(bridgedClassPrefix) else { return }
        guard let bridgedClass = bridgedSubclass(for: currentClass) else { return }
        object_setClass(window, bridgedClass)
    }

    private static func bridgedSubclass(for originalClass: AnyClass) -> AnyClass? {
        let subclassName = bridgedSubclassName(for: originalClass)
        if let existingClass = NSClassFromString(subclassName) {
            return existingClass
        }

        guard let subclass = objc_allocateClassPair(originalClass, subclassName, 0) else {
            return NSClassFromString(subclassName)
        }

        let selector = #selector(NSWindow.nextEvent(matching:until:inMode:dequeue:))
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
                    windowObject: object,
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

    private static func activeTrackingPDFView(for window: NSWindow) -> VellumPDFView? {
        (objc_getAssociatedObject(window, &trackingPDFViewKey) as? WeakPDFViewBox)?.pdfView
    }

    nonisolated private static func shouldBridgeNextEvent(
        for object: AnyObject,
        mask: UInt64,
        mode: NSString,
        dequeue: Bool
    ) -> Bool {
        guard dequeue,
              mode as String == RunLoop.Mode.eventTracking.rawValue,
              let window = object as? NSWindow else {
            return false
        }

        let requestedEvents = NSEvent.EventTypeMask(rawValue: mask)
        guard requestedEvents.contains(.leftMouseDragged) || requestedEvents.contains(.leftMouseUp) else {
            return false
        }

        return MainActor.assumeIsolated {
            guard let pdfView = activeTrackingPDFView(for: window) else { return false }
            return pdfView.shouldBridgeMouseSelectionScrollWheel
        }
    }

    nonisolated private static func replacementEventAfterConsumingScrollWheel(
        _ event: NSEvent,
        windowObject: AnyObject,
        mode: NSString,
        dequeue: Bool
    ) -> NSEvent? {
        guard dequeue,
              mode as String == RunLoop.Mode.eventTracking.rawValue,
              let window = windowObject as? NSWindow else {
            return nil
        }

        let scrollEvent = MouseSelectionScrollEvent(event)
        let replacementLocation = event.locationInWindow
        let replacementModifierFlags = event.modifierFlags
        let replacementTimestamp = event.timestamp
        let replacementWindowNumber = event.windowNumber
        let replacementEventNumber = event.eventNumber

        let didConsume = MainActor.assumeIsolated {
            guard let pdfView = activeTrackingPDFView(for: window),
                  pdfView.consumeMouseSelectionTrackingScrollWheel(scrollEvent) else {
                return false
            }

            return true
        }

        guard didConsume else { return nil }

        return NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: replacementLocation,
            modifierFlags: replacementModifierFlags,
            timestamp: replacementTimestamp,
            windowNumber: replacementWindowNumber,
            context: nil,
            eventNumber: replacementEventNumber,
            clickCount: 1,
            pressure: 0
        )
    }
}

private struct MouseSelectionScrollEvent: Sendable {
    let scrollingDeltaX: CGFloat
    let scrollingDeltaY: CGFloat
    let deltaX: CGFloat
    let deltaY: CGFloat
    let hasPreciseScrollingDeltas: Bool

    init(_ event: NSEvent) {
        scrollingDeltaX = event.scrollingDeltaX
        scrollingDeltaY = event.scrollingDeltaY
        deltaX = event.deltaX
        deltaY = event.deltaY
        hasPreciseScrollingDeltas = event.hasPreciseScrollingDeltas
    }

    var directDeltaX: CGFloat {
        directDelta(scrollingDelta: scrollingDeltaX, fallbackDelta: deltaX)
    }

    var directDeltaY: CGFloat {
        directDelta(scrollingDelta: scrollingDeltaY, fallbackDelta: deltaY)
    }

    private func directDelta(scrollingDelta: CGFloat, fallbackDelta: CGFloat) -> CGFloat {
        let rawDelta = scrollingDelta != 0 ? scrollingDelta : fallbackDelta
        return hasPreciseScrollingDeltas ? rawDelta : rawDelta * 10
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

    fileprivate func consumeMouseSelectionTrackingScrollWheel(_ event: MouseSelectionScrollEvent) -> Bool {
        guard shouldBridgeMouseSelectionScrollWheel,
              let scrollView = pdfScrollView else {
            return false
        }

        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        searchController?.markReaderNavigated()
        didDragDuringCurrentMouseSequence = true
        pendingClickHorizontalOrigin = nil

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let originBeforeScroll = clipView.bounds.origin
        let proposedOrigin = NSPoint(
            x: ScrollGeometry.nextCoordinate(
                origin: originBeforeScroll.x,
                delta: event.directDeltaX,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: ScrollGeometry.nextCoordinate(
                origin: originBeforeScroll.y,
                delta: -event.directDeltaY,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        guard proposedOrigin != originBeforeScroll else { return true }

        clipView.scroll(to: proposedOrigin)
        scrollView.reflectScrolledClipView(clipView)
        if clipView.bounds.origin != originBeforeScroll {
            scheduleReaderStateSave()
        }

        return true
    }
}

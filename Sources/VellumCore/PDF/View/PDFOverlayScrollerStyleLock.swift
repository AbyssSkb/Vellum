@preconcurrency import AppKit
import ObjectiveC.runtime

enum PDFOverlayScrollerStyleLock {
    private static let lockedClassPrefix = "VellumOverlayScrollerStyleLocked_"

    @MainActor
    static func install(on scrollView: NSScrollView) {
        guard let currentClass = object_getClass(scrollView) else {
            scrollView.scrollerStyle = .overlay
            return
        }

        if NSStringFromClass(currentClass).hasPrefix(lockedClassPrefix) {
            scrollView.scrollerStyle = .overlay
            return
        }

        guard let lockedClass = lockedSubclass(for: currentClass) else {
            scrollView.scrollerStyle = .overlay
            return
        }

        object_setClass(scrollView, lockedClass)
        scrollView.scrollerStyle = .overlay
    }

    private static func lockedSubclass(for originalClass: AnyClass) -> AnyClass? {
        let subclassName = lockedSubclassName(for: originalClass)
        if let existingClass = NSClassFromString(subclassName) {
            return existingClass
        }

        guard let subclass = objc_allocateClassPair(originalClass, subclassName, 0) else {
            return NSClassFromString(subclassName)
        }

        let selector = #selector(setter: NSScrollView.scrollerStyle)
        guard let method = class_getInstanceMethod(originalClass, selector) else {
            objc_disposeClassPair(subclass)
            return nil
        }

        let originalImplementation = method_getImplementation(method)
        typealias Setter = @convention(c) (AnyObject, Selector, NSScroller.Style) -> Void
        let originalSetter = unsafeBitCast(originalImplementation, to: Setter.self)
        let lockedSetter: @convention(block) (AnyObject, NSScroller.Style) -> Void = { object, style in
            originalSetter(object, selector, style == .legacy ? .overlay : style)
        }

        guard class_addMethod(
            subclass,
            selector,
            imp_implementationWithBlock(lockedSetter),
            method_getTypeEncoding(method)
        ) else {
            objc_disposeClassPair(subclass)
            return nil
        }

        objc_registerClassPair(subclass)
        return subclass
    }

    private static func lockedSubclassName(for originalClass: AnyClass) -> String {
        let originalName = NSStringFromClass(originalClass)
        let sanitizedName = originalName.map { character in
            character.isLetter || character.isNumber || character == "_" ? character : "_"
        }

        return lockedClassPrefix + String(sanitizedName)
    }
}

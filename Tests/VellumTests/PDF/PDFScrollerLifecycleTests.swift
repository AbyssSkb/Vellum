import AppKit
import ObjectiveC.runtime
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF scroll view KVO teardown")
struct PDFScrollerLifecycleTests {
    @Test(arguments: [true, false], [true, false])
    func overlayLockReleasesKVOObservedScrollView(observeBeforeLock: Bool, observeScrollerStyle: Bool) throws {
        _ = NSApplication.shared
        weak var releasedScrollView: NSScrollView?
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }

        try autoreleasepool {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            releasedScrollView = scrollView
            if !observeBeforeLock { PDFOverlayScrollerStyleLock.install(on: scrollView) }
            let classBeforeObservation = try #require(object_getClass(scrollView))
            observation = observeScrollerStyle
                ? scrollView.observe(\.scrollerStyle) { _, _ in }
                : scrollView.observe(\.contentInsets) { _, _ in }
            let observedClass = try #require(object_getClass(scrollView))
            try #require(ObjectIdentifier(observedClass) != ObjectIdentifier(classBeforeObservation))
            if observeBeforeLock { PDFOverlayScrollerStyleLock.install(on: scrollView) }
            #expect(object_getClass(scrollView) === observedClass)
            scrollView.scrollerStyle = .legacy
            #expect(scrollView.scrollerStyle == .overlay)
        }

        #expect(releasedScrollView == nil)
        observation?.invalidate()
        observation = nil
        autoreleasepool {}
        #expect(releasedScrollView == nil)
    }
}

@preconcurrency import AppKit
import QuartzCore
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF outline title")
struct PDFOutlineTitleViewTests {
    @Test(arguments: [15.0, 180.0])
    func shortAndLongOverflowsMoveAtTheSameSpeed(overflow: Double) throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        _ = NSApplication.shared
        let view = PDFOutlineTitleView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        view.title = "A long chapter title that cannot fit in this outline row"
        let width = ceil(view.intrinsicContentSize.width) - CGFloat(overflow)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 20),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        view.isSelected = true
        let marqueeLayer = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first)
        let key = try #require(marqueeLayer.animationKeys()?.first)
        let animation = try #require(marqueeLayer.animation(forKey: key) as? CAKeyframeAnimation)
        let times = try #require(animation.keyTimes).map(\.doubleValue)
        let values = try #require(animation.values as? [NSNumber]).map(\.doubleValue)
        try #require(times.count == 4 && values.count == 4)

        let travelTime = (times[2] - times[1]) * animation.duration
        let speed = abs(values[2] - values[1]) / travelTime
        #expect(abs(speed - 30) < 0.0001)
        #expect(abs((times[1] - times[0]) * animation.duration - 1.5) < 0.0001)
        #expect(abs((times[3] - times[2]) * animation.duration - 1.5) < 0.0001)
        #expect(animation.calculationMode == .linear)
        let timing = try #require(animation.timingFunction)
        for function in [timing] + (animation.timingFunctions ?? []) {
            for index in 1...2 {
                var point: [Float] = [0, 0]
                function.getControlPoint(at: index, values: &point)
                #expect(point[0] == point[1])
            }
        }
    }

    @Test
    func selectedClippedTitleScrollsAndResetsWhenDeselectedOrFitting() throws {
        _ = NSApplication.shared
        let view = PDFOutlineTitleView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        view.title = "A long chapter title that cannot fit in this outline row"
        let window = NSWindow(
            contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        let marqueeLayer = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first)

        #expect(view.textField.lineBreakMode == .byTruncatingTail)
        #expect(marqueeLayer.animationKeys()?.isEmpty != false)
        #expect(marqueeLayer.isHidden)
        view.isSelected = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(marqueeLayer.animationKeys()?.isEmpty != false)
            #expect(view.textField.lineBreakMode == .byTruncatingTail)
            #expect(view.toolTip == view.title)
        } else {
            let key = try #require(marqueeLayer.animationKeys()?.first)
            let animation = try #require(marqueeLayer.animation(forKey: key) as? CAKeyframeAnimation)
            #expect(animation.keyPath == "transform.translation.x")
            #expect(animation.repeatCount == .infinity)
            #expect((marqueeLayer.string as? NSAttributedString)?.string == view.title)
            #expect(marqueeLayer.frame.width > view.bounds.width)
            #expect(!marqueeLayer.isHidden)
            #expect(view.textField.layer?.opacity == 0)
            #expect(!view.textField.isHidden)
            #expect(view.layer?.masksToBounds == true)
        }

        view.isSelected = false
        #expect(marqueeLayer.animationKeys()?.isEmpty != false)
        #expect(marqueeLayer.isHidden)
        #expect(view.textField.layer?.opacity == 1)
        #expect(view.textField.lineBreakMode == .byTruncatingTail)
        #expect(view.textField.frame.width == view.bounds.width)
        #expect(CATransform3DIsIdentity(marqueeLayer.transform))

        view.isSelected = true
        window.setContentSize(NSSize(width: view.intrinsicContentSize.width + 20, height: 20))
        view.layoutSubtreeIfNeeded()
        #expect(marqueeLayer.animationKeys()?.isEmpty != false)
        #expect(marqueeLayer.isHidden)
        #expect(view.textField.layer?.opacity == 1)
        #expect(view.textField.lineBreakMode == .byTruncatingTail)
        #expect(view.textField.frame.width == view.bounds.width)
    }
}

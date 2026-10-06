@preconcurrency import AppKit
import QuartzCore
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF outline title")
struct PDFOutlineTitleViewTests {
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

@preconcurrency import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Clipped tab title")
struct ClippedTabTitleTests {
    @Test
    func clippedTitlesLoopOnlyWhenSelectedOrHoveredAndPreserveProgress() async throws {
        _ = NSApplication.shared
        let title = "A long document filename that cannot fit inside this tab.pdf"
        let host = NSHostingView(rootView: ClippedTabTitle(title: title, isSelected: false)
            .frame(width: 100, height: 20))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 20),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        func update(selected: Bool, hovered: Bool, name: String? = nil) async throws {
            host.rootView = ClippedTabTitle(title: name ?? title, isSelected: selected, isHovered: hovered)
                .frame(width: 100, height: 20)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        try await update(selected: false, hovered: false)
        let view = try #require(descendants(host).compactMap { $0 as? PDFOutlineTitleView }.first)
        let layer = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first)
        let animationKey = "outlineTitleScroll"
        #expect(view.bounds.width == 100)
        #expect(view.textField.lineBreakMode == .byTruncatingTail)
        #expect(!view.textField.isSelectable)
        #expect(view.textField.stringValue == title)
        #expect(view.textField.textColor == TokyoNight.muted)
        #expect(layer.isHidden)

        for selected in [true, false] {
            try await update(selected: selected, hovered: !selected)
            #expect(view.textField.font == NSFont.systemFont(ofSize: 12.5, weight: selected ? .medium : .regular))
            #expect(view.textField.textColor == TokyoNight.foreground)
            #expect(view.toolTip == title)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(layer.isHidden)
                #expect(layer.animation(forKey: animationKey) == nil)
            } else {
                let animation = try #require(layer.animation(forKey: animationKey)?.copy() as? CAAnimation)
                #expect(!layer.isHidden)
                #expect((layer.string as? NSAttributedString)?.string == title)
                #expect(animation.repeatCount == .infinity)
                let beginTime = CACurrentMediaTime() - 2
                animation.beginTime = beginTime
                layer.add(animation, forKey: animationKey)
                try await update(selected: selected, hovered: !selected)
                #expect(layer.animation(forKey: animationKey)?.beginTime == beginTime)
            }
        }

        try await update(selected: false, hovered: false)
        #expect(layer.isHidden)
        #expect(layer.animation(forKey: animationKey) == nil)
        #expect(view.textField.layer?.opacity == 1)
        #expect(CATransform3DIsIdentity(layer.transform))

        try await update(selected: true, hovered: false, name: "Short.pdf")
        #expect(view.title == "Short.pdf")
        #expect(layer.isHidden)
        #expect(layer.animation(forKey: animationKey) == nil)
        #expect(view.textField.layer?.opacity == 1)
    }
}

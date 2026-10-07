@preconcurrency import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Clipped tab title")
struct ClippedTabTitleTests {
    @Test
    func initialZeroWidthWaitsForLayoutAndHeightChangesPreserveSinglePlayback() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        _ = NSApplication.shared
        let view = PDFOutlineTitleView(frame: .zero)
        view.repeatsMarquee = false
        view.title = "A long document filename that cannot fit inside this tab.pdf"
        view.playMarqueeOnce()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        container.addSubview(view)
        let window = NSWindow(
            contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFront(nil)
        defer { window.close() }
        let layer = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first)
        let key = "outlineTitleScroll"
        #expect(layer.animation(forKey: key) == nil)

        view.setFrameSize(NSSize(width: 100, height: 20))
        let animation = try #require(layer.animation(forKey: key)?.copy() as? CAAnimation)
        #expect(animation.repeatCount == 0)
        let beginTime = CACurrentMediaTime() - 1
        animation.beginTime = beginTime
        layer.add(animation, forKey: key)
        view.setFrameSize(NSSize(width: 100, height: 28))
        view.layoutSubtreeIfNeeded()
        #expect(layer.animation(forKey: key)?.beginTime == beginTime)

        view.animationDidStop(animation, finished: true)
        view.setFrameSize(NSSize(width: 100, height: 20))
        view.layoutSubtreeIfNeeded()
        #expect(layer.animation(forKey: key) == nil)
        #expect(layer.isHidden)
    }

    @Test
    func clippedTitlesPlayOnceOnActivationAndHoverWithoutReplayingDuringUpdates() async throws {
        _ = NSApplication.shared
        let title = "A long document filename that cannot fit inside this tab.pdf"
        let host = NSHostingView(rootView: ClippedTabTitle(title: title, isSelected: true)
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

        try await update(selected: true, hovered: false)
        let view = try #require(descendants(host).compactMap { $0 as? PDFOutlineTitleView }.first)
        let layer = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first)
        let animationKey = "outlineTitleScroll"
        #expect(view.bounds.width == 100)
        #expect(view.textField.lineBreakMode == .byTruncatingTail)
        #expect(!view.textField.isSelectable)
        #expect(view.textField.stringValue == title)
        #expect(view.textField.textColor == TokyoNight.foreground)
        #expect(!view.repeatsMarquee)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(layer.isHidden)
            #expect(layer.animation(forKey: animationKey) == nil)
            return
        }

        func animation() throws -> CAAnimation {
            try #require(layer.animation(forKey: animationKey)?.copy() as? CAAnimation)
        }
        func finishPlayback() throws {
            view.animationDidStop(try animation(), finished: true)
            #expect(layer.isHidden)
            #expect(layer.animation(forKey: animationKey) == nil)
            #expect(view.textField.layer?.opacity == 1)
            #expect(CATransform3DIsIdentity(layer.transform))
        }

        // The newly opened, initially selected tab plays without a selection transition.
        #expect(try animation().repeatCount == 0)
        try finishPlayback()
        try await update(selected: true, hovered: false)
        view.layoutSubtreeIfNeeded()
        view.setFrameSize(NSSize(width: 80, height: 20))
        view.setFrameSize(NSSize(width: 100, height: 20))
        #expect(layer.animation(forKey: animationKey) == nil)

        for selected in [true, false] {
            try await update(selected: false, hovered: false)
            try await update(selected: selected, hovered: !selected)
            #expect(view.textField.font == NSFont.systemFont(ofSize: 12.5, weight: selected ? .medium : .regular))
            #expect(view.textField.textColor == TokyoNight.foreground)
            #expect(view.toolTip == title)
            let currentAnimation = try animation()
            #expect(!layer.isHidden)
            #expect((layer.string as? NSAttributedString)?.string == title)
            #expect(currentAnimation.repeatCount == 0)
            let beginTime = CACurrentMediaTime() - 2
            currentAnimation.beginTime = beginTime
            layer.add(currentAnimation, forKey: animationKey)
            try await update(selected: selected, hovered: !selected)
            #expect(layer.animation(forKey: animationKey)?.beginTime == beginTime)
            try finishPlayback()
            try await update(selected: selected, hovered: !selected)
            #expect(layer.animation(forKey: animationKey) == nil)
        }

        // Leaving a hovered tab restores its static title; entering it again plays once.
        try await update(selected: false, hovered: false)
        try await update(selected: false, hovered: true)
        let stoppedAnimation = try animation()
        try await update(selected: false, hovered: false)
        try await update(selected: false, hovered: true)
        view.animationDidStop(stoppedAnimation, finished: true)
        #expect(try animation().repeatCount == 0)
        try await update(selected: false, hovered: false)
        #expect(layer.isHidden)
        #expect(layer.animation(forKey: animationKey) == nil)
        #expect(view.textField.layer?.opacity == 1)
        #expect(CATransform3DIsIdentity(layer.transform))

        try await update(selected: true, hovered: true)
        try finishPlayback()
        try await update(selected: true, hovered: true)
        #expect(layer.animation(forKey: animationKey) == nil)

        // A new filename in an already selected tab is another activation.
        try await update(selected: true, hovered: true, name: title + " (revised)")
        #expect(try animation().repeatCount == 0)
        try finishPlayback()

        try await update(selected: true, hovered: false, name: "Short.pdf")
        #expect(view.title == "Short.pdf")
        #expect(layer.isHidden)
        #expect(layer.animation(forKey: animationKey) == nil)
        #expect(view.textField.layer?.opacity == 1)
        view.setFrameSize(NSSize(width: 10, height: 20))
        #expect(layer.animation(forKey: animationKey) == nil)
    }
}

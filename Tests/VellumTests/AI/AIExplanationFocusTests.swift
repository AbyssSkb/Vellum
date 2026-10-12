@preconcurrency import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("AI explanation focus")
struct AIExplanationFocusTests {
    @Test
    func updatesAndOldOverlayCallbacksPreserveTheCurrentResponder() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let reader = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = reader
        let outline = PDFOutlineKeyView(frame: .zero)
        reader.addSubview(outline)
        defer { reader.hideAIExplanationPopover(); window.contentView = nil; window.close() }
        func registeredWebView() async throws -> AIExplanationWebView {
            try await waitForTestCondition("The explanation web view is registered") {
                reader.layoutSubtreeIfNeeded()
                return reader.aiInteraction.activeWebView != nil
            }
            let webView = try #require(reader.aiInteraction.activeWebView)
            webView.stopLoading()
            return webView
        }
        func expectFocus(_ responder: NSResponder) {
            let hasExpectedFocus = window.firstResponder === responder
            #expect(hasExpectedFocus)
        }
        let model = AIExplanationPopoverModel(title: "Explanation", text: "Beginning", isStreaming: true)
        #expect(window.makeFirstResponder(outline))
        reader.showPopover(model: model, at: nil, kind: .streaming)
        let webView = try await registeredWebView()
        let overlay = try #require(reader.aiInteraction.explanationOverlay)
        let hostingView = try #require(overlay.subviews.first as? NSHostingView<AppLanguageObservedView<AIExplanationPopoverView>>)
        let oldContent = hostingView.rootView.content
        webView.webView(webView, didFinish: nil)
        expectFocus(webView)

        #expect(window.makeFirstResponder(outline))
        model.append(" more streamed text")
        reader.layoutSubtreeIfNeeded()
        await nextTestMainQueueTurn()
        webView.webView(webView, didFinish: nil)
        expectFocus(outline)

        let replacement = AIExplanationPopoverModel(title: "New explanation", text: "Replacement", isStreaming: true)
        reader.showPopover(model: replacement, at: nil, kind: .streaming)
        let replacementWebView = try await registeredWebView()
        let replacedWebView = replacementWebView !== webView
        #expect(replacedWebView)
        #expect(window.makeFirstResponder(outline))
        reader.aiInteraction.popoverHeightUpdateWorkItem?.cancel()
        reader.aiInteraction.popoverHeightUpdateWorkItem = nil
        reader.aiInteraction.pendingPopoverContentHeight = nil
        oldContent.onWebViewReady(webView)
        oldContent.onContentHeightChange(400)
        oldContent.onDismiss()
        oldContent.onHighlight()
        oldContent.onCycleColor()
        _ = webView.onInitialFocus?()
        #expect(reader.aiInteraction.popoverHeightUpdateWorkItem == nil)
        #expect(reader.aiInteraction.activeExplanationModel === replacement)
        await nextTestMainQueueTurn()
        let retainedCurrentWebView = reader.aiInteraction.activeWebView === replacementWebView
        #expect(retainedCurrentWebView)
        expectFocus(outline)

        reader.hideAIExplanationPopover()
        oldContent.onWebViewReady(webView)
        _ = webView.onInitialFocus?()
        await nextTestMainQueueTurn()
        let removedWebView = reader.aiInteraction.activeWebView == nil
        #expect(removedWebView)
        expectFocus(outline)

        reader.showPopover(model: AIExplanationPopoverModel(title: "Hover", text: "Saved answer"), at: nil, kind: .hover)
        _ = try await registeredWebView()
        window.orderFront(nil)
        #expect(window.makeFirstResponder(outline))
        reader.restoreAIFloatingOverlayPresentation()
        expectFocus(outline)
    }

    @Test
    func deferredWebFocusRetriesOnlyWhileItsOverlayStillOwnsTheResponder() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
        let window = AIExplanationFocusWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let otherWindow = AIExplanationFocusWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        otherWindow.isReleasedWhenClosed = false
        let reader = VellumPDFView(frame: window.contentView!.bounds)
        reader.appState = appState
        appState.activeReaderController = reader
        appState.readerWindow = window
        window.ownsKeyFocus = true
        window.contentView = reader
        defer {
            reader.hideAIExplanationPopover()
            window.contentView = nil
            otherWindow.contentView = nil
            otherWindow.close()
            window.close()
        }
        window.orderFront(nil)
        let model = AIExplanationPopoverModel(title: "Deferred explanation", text: "Answer")
        reader.showPopover(model: model, at: nil, kind: .message)
        try await waitForTestCondition("The deferred explanation web view is registered") {
            reader.layoutSubtreeIfNeeded()
            return reader.aiInteraction.activeWebView != nil
        }
        reader.aiInteraction.activeWebView?.stopLoading()
        let overlay = try #require(reader.aiInteraction.explanationOverlay)
        let hostingView = try #require(overlay.subviews.first as? NSHostingView<AppLanguageObservedView<AIExplanationPopoverView>>)
        reader.aiInteraction.activeWebView?.shouldFocusWhenReady = false

        func deferredWebView() -> AIExplanationWebView {
            let webView = AIExplanationWebView()
            webView.stopLoading()
            hostingView.rootView.content.onWebViewReady(webView)
            overlay.addSubview(webView)
            reader.aiInteraction.activeWebView = webView
            return webView
        }
        let webView = deferredWebView()
        #expect(window.makeFirstResponder(overlay))
        window.ownsKeyFocus = false
        otherWindow.ownsKeyFocus = true
        #expect(!appState.canFocusReaderContent)
        webView.webView(webView, didFinish: nil)
        let deferredFocusStayedPending = window.firstResponder === overlay
        #expect(deferredFocusStayedPending)
        otherWindow.ownsKeyFocus = false
        window.ownsKeyFocus = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        let receivedDeferredFocus = window.firstResponder === webView
        #expect(receivedDeferredFocus)

        let waitingWebView = deferredWebView()
        #expect(window.makeFirstResponder(overlay))
        window.ownsKeyFocus = false
        otherWindow.ownsKeyFocus = true
        waitingWebView.webView(waitingWebView, didFinish: nil)
        let outline = PDFOutlineKeyView(frame: .zero)
        reader.addSubview(outline)
        #expect(window.makeFirstResponder(outline))
        otherWindow.ownsKeyFocus = false
        window.ownsKeyFocus = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        let preservedOutlineFocus = window.firstResponder === outline
        #expect(preservedOutlineFocus)
        reader.hideAIExplanationPopover()
        waitingWebView.requestInitialFocus()
        let removedOverlayStayedUnfocused = window.firstResponder === outline
        #expect(removedOverlayStayedUnfocused)
    }
}

private final class AIExplanationFocusWindow: NSWindow {
    var ownsKeyFocus = false
    override var isKeyWindow: Bool { ownsKeyFocus }
}

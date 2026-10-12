import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("AI conversation composer")
@MainActor
struct AIConversationComposerTests {
    @Test(arguments: [UInt16(36), 76])
    func returnCommitsMarkedTextWithoutSending(keyCode: UInt16) throws {
        let window = makeWindow()
        defer { window.contentView = nil; window.close() }
        let textView = AIConversationNSTextView(frame: window.contentView!.bounds)
        textView.shouldFocusWhenAttached = false
        window.contentView = textView
        #expect(window.makeFirstResponder(textView))
        var sends = 0
        textView.onCommandReturn = { sends += 1 }
        textView.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.hasMarkedText())
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: keyCode
        ))

        textView.keyDown(with: event)
        #expect(sends == 0)
        textView.unmarkText()
        textView.keyDown(with: event)
        #expect(sends == 1)
    }

    @Test
    func longComposerKeepsFullScrollableDocumentHeight() {
        let window = makeWindow()
        defer { window.contentView = nil; window.close() }
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        window.contentView = scrollView
        let textView = NSTextView(frame: scrollView.bounds)
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 11)
        textView.string = String(repeating: "Long draft line\n", count: 100)
        scrollView.documentView = textView
        var viewportHeight: CGFloat = 0
        let coordinator = AIConversationInputTextView.Coordinator(
            text: .constant(textView.string), isFocused: .constant(false), onHeightChange: { viewportHeight = $0 }
        )

        coordinator.reportTextHeight(in: scrollView)
        #expect(viewportHeight == AIConversationPopoverMetrics.maximumHeight - AIConversationPopoverMetrics.composerOuterVerticalPadding)
        #expect(textView.frame.height > AIConversationPopoverMetrics.maximumHeight)
        textView.scrollRangeToVisible(NSRange(location: textView.string.utf16.count, length: 0))
        #expect(scrollView.contentView.bounds.minY > AIConversationPopoverMetrics.maximumHeight)
    }

    @Test
    func escapeLetsTheComposerCancelMarkedTextBeforeClosingAI() throws {
        let window = makeWindow()
        defer { window.contentView = nil; window.close() }
        let reader = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = reader
        let editor = AIConversationNSTextView(frame: reader.bounds)
        editor.shouldFocusWhenAttached = false
        reader.addSubview(editor)
        let model = AIConversationPopoverModel(context: Self.context())
        reader.aiInteraction.activeConversationModel = model
        #expect(window.makeFirstResponder(editor))
        editor.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        #expect(!reader.handleAIKeyEvent(event))
        #expect(reader.aiInteraction.activeConversationModel === model)
        editor.unmarkText()
        #expect(reader.handleAIKeyEvent(event))
        #expect(reader.aiInteraction.activeConversationModel == nil)
    }

    @Test
    func streamingUpdatePreservesComposerSelection() async throws {
        let window = makeWindow()
        defer { window.contentView = nil; window.close() }
        let model = AIConversationPopoverModel(context: Self.context())
        model.draft = "A question in progress"
        model.messages = [AIConversationMessage(role: .assistant, content: "Beginning")]
        _ = model.refreshPreferredHeight()
        var presentedHeight: CGFloat?
        let hostingView = NSHostingView(rootView: AIConversationPopoverView(
            model: model, onDismiss: {}, onSend: { _ in true },
            onPreferredSizeChange: { presentedHeight = $0.height }
        ))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        try await waitForTestCondition("The conversation composer is mounted") {
            hostingView.layoutSubtreeIfNeeded()
            return composer(in: hostingView) != nil && presentedHeight == model.preferredHeight
        }
        await nextTestMainQueueTurn()
        let editor = try #require(composer(in: hostingView))
        #expect(window.makeFirstResponder(editor))
        let selection = NSRange(location: 2, length: 5)
        editor.setSelectedRange(selection)

        model.appendToLatestAssistant(" more streamed text")
        _ = model.updateMessageContentHeight(180)
        try await waitForTestCondition("The streamed conversation has updated its native layout") {
            hostingView.layoutSubtreeIfNeeded()
            return presentedHeight == model.preferredHeight
        }
        await nextTestMainQueueTurn()

        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == selection)
        #expect(model.draft == "A question in progress")

        let otherEditor = NSTextView()
        hostingView.addSubview(otherEditor)
        #expect(window.makeFirstResponder(otherEditor))
        model.appendToLatestAssistant(" another chunk")
        presentedHeight = nil
        _ = model.updateMessageContentHeight(210)
        try await waitForTestCondition("The next streamed update has completed") {
            hostingView.layoutSubtreeIfNeeded()
            return presentedHeight == model.preferredHeight
        }
        await nextTestMainQueueTurn()
        #expect(window.firstResponder === otherEditor)
    }

    @Test
    func deferredComposerFocusKeepsTheCurrentResponderAndOverlay() async {
        let window = makeWindow()
        defer { window.contentView = nil; window.close() }
        let reader = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = reader
        let overlay = NSView(frame: reader.bounds)
        reader.addSubview(overlay)
        reader.aiInteraction.conversationOverlay = overlay
        let editor = AIConversationNSTextView(frame: overlay.bounds)
        overlay.addSubview(editor)
        let otherEditor = NSTextView(frame: reader.bounds)
        reader.addSubview(otherEditor)

        await nextTestMainQueueTurn()
        let receivedInitialFocus = window.firstResponder === editor
        #expect(receivedInitialFocus)

        editor.requestFocusAndShowInsertionPoint()
        #expect(window.makeFirstResponder(otherEditor))
        await nextTestMainQueueTurn()
        let preservedNewResponder = window.firstResponder === otherEditor
        #expect(preservedNewResponder)

        editor.requestFocusAndShowInsertionPoint()
        editor.shouldFocusWhenAttached = false
        await nextTestMainQueueTurn()
        let canceledFocus = window.firstResponder === otherEditor
        #expect(canceledFocus)

        editor.shouldFocusWhenAttached = true
        editor.requestFocusAndShowInsertionPoint()
        editor.removeFromSuperview()
        await nextTestMainQueueTurn()
        let detachedViewStayedUnfocused = window.firstResponder === otherEditor
        #expect(detachedViewStayedUnfocused)

        overlay.addSubview(editor)
        reader.aiInteraction.conversationOverlay = nil
        await nextTestMainQueueTurn()
        let replacedOverlayStayedUnfocused = window.firstResponder === otherEditor
        #expect(replacedOverlayStayedUnfocused)

        reader.aiInteraction.conversationOverlay = overlay
        editor.requestFocusAndShowInsertionPoint()
        await nextTestMainQueueTurn()
        let receivedExplicitFocus = window.firstResponder === editor
        #expect(receivedExplicitFocus)
    }

    @Test
    func dismissingConversationReleasesItsOverlay() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        weak var overlay: NSView?
        autoreleasepool {
            view.showAIConversationPopover(model: AIConversationPopoverModel(context: Self.context()))
            overlay = view.aiInteraction.conversationOverlay
            #expect(overlay != nil)
            view.dismissActiveAIInteraction(clearSelection: true)
        }
        #expect(overlay == nil)
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func composer(in view: NSView) -> AIConversationNSTextView? {
        if let editor = view as? AIConversationNSTextView { return editor }
        return view.subviews.lazy.compactMap(composer).first
    }

    private static func context() -> AIExplanationContext {
        AIExplanationContext(
            selectedText: "selected",
            currentParagraph: "selected paragraph",
            nearbyText: "nearby",
            fileName: "paper.pdf",
            directoryName: nil,
            outlineTitle: nil,
            pageNumbers: [1]
        )
    }
}

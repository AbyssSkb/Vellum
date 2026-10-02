import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("AI conversation popover model")
@MainActor
struct AIConversationPopoverModelTests {
    @Test
    func emptyPopoverHeightFollowsComposerTextHeight() {
        let model = AIConversationPopoverModel(context: Self.context())
        let measuredTextHeight = AIConversationPopoverMetrics.composerTextMinimumHeight + 42

        let didResize = model.updateComposerTextHeight(measuredTextHeight)

        #expect(didResize)
        #expect(model.composerTextHeight == ceil(measuredTextHeight))
        #expect(model.preferredHeight == model.composerHeight)
    }

    @Test
    func messageHeightRecalculatesWithDynamicComposerHeight() {
        let model = AIConversationPopoverModel(context: Self.context())
        model.messages = [
            AIConversationMessage(role: .user, content: "How should I read this?")
        ]

        _ = model.updateMessageContentHeight(120)
        #expect(model.preferredHeight == 120 + AIConversationPopoverMetrics.dividerHeight + model.composerHeight)

        _ = model.updateComposerTextHeight(92)
        #expect(model.preferredHeight == 120 + AIConversationPopoverMetrics.dividerHeight + model.composerHeight)
    }

    @Test
    func transcriptScrollRequestOnlyChangesWhenExplicitlyRequested() {
        let model = AIConversationPopoverModel(context: Self.context())
        let initialGeneration = model.transcriptScrollToBottomGeneration

        _ = model.updateComposerTextHeight(92)
        model.draft = "A longer prompt that resizes the composer."
        model.messages = [
            AIConversationMessage(role: .assistant, content: "Existing answer")
        ]
        #expect(model.transcriptScrollToBottomGeneration == initialGeneration)

        model.requestTranscriptScrollToBottom()
        #expect(model.transcriptScrollToBottomGeneration == initialGeneration + 1)
    }

    @Test(arguments: [false, true])
    func draftClearsOnlyAfterSendIsAccepted(accepted: Bool) {
        let model = AIConversationPopoverModel(context: Self.context())
        model.draft = "  Keep this question  "
        var receivedPrompt: String?

        #expect(model.submitDraft { prompt in
            receivedPrompt = prompt
            return accepted
        } == accepted)

        #expect(receivedPrompt == "Keep this question")
        #expect(model.draft == (accepted ? "" : "  Keep this question  "))
        #expect(model.transcriptScrollToBottomGeneration == (accepted ? 1 : 0))
    }

    @Test(arguments: [UInt16(36), 76])
    func returnCommitsMarkedTextWithoutSending(keyCode: UInt16) throws {
        let window = makeWindow()
        defer { window.close() }
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
        defer { window.close() }
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
    func streamingUpdatePreservesComposerSelection() throws {
        let window = makeWindow()
        defer { window.close() }
        let model = AIConversationPopoverModel(context: Self.context())
        model.draft = "A question in progress"
        model.messages = [AIConversationMessage(role: .assistant, content: "Beginning")]
        _ = model.refreshPreferredHeight()
        let hostingView = NSHostingView(rootView: AIConversationPopoverView(
            model: model, onDismiss: {}, onSend: { _ in true }, onPreferredSizeChange: { _ in }
        ))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let editor = try #require(composer(in: hostingView))
        #expect(window.makeFirstResponder(editor))
        let selection = NSRange(location: 2, length: 5)
        editor.setSelectedRange(selection)

        model.appendToLatestAssistant(" more streamed text")
        _ = model.updateMessageContentHeight(180)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == selection)
        #expect(model.draft == "A question in progress")

        let otherEditor = NSTextView()
        hostingView.addSubview(otherEditor)
        #expect(window.makeFirstResponder(otherEditor))
        model.appendToLatestAssistant(" another chunk")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(window.firstResponder === otherEditor)
    }

    @Test
    func dismissingConversationReleasesItsOverlay() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        weak var overlay: NSView?
        autoreleasepool {
            view.showAIConversationPopover(model: AIConversationPopoverModel(context: Self.context()), at: nil)
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

@preconcurrency import AppKit
import PDFKit

@MainActor
final class AIInteractionState {
    var explanationPopover: NSPopover?
    var explanationWindow: NSWindow?
    var activeExplanationModel: AIExplanationPopoverModel?
    var conversationPopover: NSPopover?
    var conversationWindow: NSWindow?
    var activeConversationModel: AIConversationPopoverModel?
    var activeSelection: PDFSelection?
    var existingAnnotations: [PDFAnnotation] = []
    var explanationTask: Task<Void, Never>?
    var conversationTask: Task<Void, Never>?
    weak var activeWebView: AIExplanationWebView?
    var continuousScrollKey: String?
    var pendingPopoverContentHeight: CGFloat?
    var popoverHeightUpdateWorkItem: DispatchWorkItem?
    weak var hoveredAnnotation: PDFAnnotation?
    var hoveredText: String?
    var hoveredKey: String?
    var suppressedHoverKey: String?
    weak var suppressedHoverAnnotation: PDFAnnotation?
    var suppressedHoverText: String?
    var hoverPopoverHideWorkItem: DispatchWorkItem?
    weak var toastView: NSView?
    var toastHideWorkItem: DispatchWorkItem?
    var floatingWindowDismissMonitor: Any?

    var isActive: Bool {
        explanationPopover?.isShown == true
            || explanationWindow?.isVisible == true
            || activeExplanationModel != nil
            || conversationPopover?.isShown == true
            || conversationWindow?.isVisible == true
            || activeConversationModel != nil
    }

    func clearActiveRequest() {
        explanationTask?.cancel()
        explanationTask = nil
        conversationTask?.cancel()
        conversationTask = nil
        activeSelection = nil
        existingAnnotations = []
    }

    func clearPopoverState() {
        popoverHeightUpdateWorkItem?.cancel()
        popoverHeightUpdateWorkItem = nil
        pendingPopoverContentHeight = nil
        explanationPopover?.close()
        explanationPopover = nil
        if let floatingWindowDismissMonitor {
            NSEvent.removeMonitor(floatingWindowDismissMonitor)
        }
        floatingWindowDismissMonitor = nil
        if let explanationWindow {
            explanationWindow.parent?.removeChildWindow(explanationWindow)
            explanationWindow.close()
        }
        explanationWindow = nil
        activeExplanationModel = nil
        conversationPopover?.close()
        conversationPopover = nil
        if let conversationWindow {
            conversationWindow.parent?.removeChildWindow(conversationWindow)
            conversationWindow.close()
        }
        conversationWindow = nil
        activeConversationModel = nil
        activeWebView = nil
        hoveredAnnotation = nil
        hoveredText = nil
        hoveredKey = nil
        toastHideWorkItem?.cancel()
        toastHideWorkItem = nil
        toastView?.removeFromSuperview()
        toastView = nil
    }

    func clearSuppressedHover() {
        suppressedHoverKey = nil
        suppressedHoverAnnotation = nil
        suppressedHoverText = nil
    }
}

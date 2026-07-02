@preconcurrency import AppKit
import PDFKit

@MainActor
final class AIInteractionState {
    var explanationPopover: NSPopover?
    var activeExplanationModel: AIExplanationPopoverModel?
    var conversationPopover: NSPopover?
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

    var isActive: Bool {
        explanationPopover?.isShown == true
            || activeExplanationModel != nil
            || conversationPopover?.isShown == true
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
        activeExplanationModel = nil
        conversationPopover?.close()
        conversationPopover = nil
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

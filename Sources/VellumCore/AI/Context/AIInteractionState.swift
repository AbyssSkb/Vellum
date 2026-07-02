@preconcurrency import AppKit
import PDFKit

@MainActor
final class AIInteractionState {
    var explanationPopover: NSPopover?
    var explanationOverlay: NSView?
    var activeExplanationModel: AIExplanationPopoverModel?
    var conversationPopover: NSPopover?
    var conversationOverlay: NSView?
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
    var floatingOverlayDismissMonitor: Any?
    var floatingOverlayActivationObserver: NSObjectProtocol?

    var isActive: Bool {
        explanationPopover?.isShown == true
            || explanationOverlay?.superview != nil
            || activeExplanationModel != nil
            || conversationPopover?.isShown == true
            || conversationOverlay?.superview != nil
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
        if let floatingOverlayDismissMonitor {
            NSEvent.removeMonitor(floatingOverlayDismissMonitor)
        }
        floatingOverlayDismissMonitor = nil
        if let floatingOverlayActivationObserver {
            NotificationCenter.default.removeObserver(floatingOverlayActivationObserver)
        }
        floatingOverlayActivationObserver = nil
        explanationOverlay?.removeFromSuperview()
        explanationOverlay = nil
        activeExplanationModel = nil
        conversationPopover?.close()
        conversationPopover = nil
        conversationOverlay?.removeFromSuperview()
        conversationOverlay = nil
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

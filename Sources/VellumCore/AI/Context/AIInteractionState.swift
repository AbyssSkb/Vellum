@preconcurrency import AppKit
import PDFKit

@MainActor
final class AIInteractionState {
    var explanationPopover: NSPopover?
    var activeExplanationModel: AIExplanationPopoverModel?
    var activeSelection: PDFSelection?
    var existingAnnotations: [PDFAnnotation] = []
    var explanationTask: Task<Void, Never>?
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

    var isActive: Bool {
        explanationPopover?.isShown == true || activeExplanationModel != nil
    }

    func clearActiveRequest() {
        explanationTask?.cancel()
        explanationTask = nil
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
        activeWebView = nil
        hoveredAnnotation = nil
        hoveredText = nil
        hoveredKey = nil
    }

    func clearSuppressedHover() {
        suppressedHoverKey = nil
        suppressedHoverAnnotation = nil
        suppressedHoverText = nil
    }
}

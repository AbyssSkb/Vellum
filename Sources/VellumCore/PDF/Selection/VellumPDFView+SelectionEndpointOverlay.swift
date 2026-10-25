@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func updateSelectionEndpointOverlay() {
        guard let document,
              currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              !isMouseSelectingText, !isAIInteractionActive, !isPageOverviewActive, !isWordJumpActive,
              referenceController?.isPreviewActive != true,
              appState == nil || appState?.activeReaderController === self,
              let responder = window?.firstResponder as? NSView,
              responder === self || responder.isDescendant(of: self),
              !(responder is NSText), !(responder is NSTextField),
              let state = textSelectionNavigationState,
              let caret = state.extentCaret,
              let page = document.page(at: caret.pageIndex),
              currentSelection?.pages.contains(where: { $0 === page }) == true else {
            selectionEndpointOverlay?.isHidden = true
            return
        }

        let pageStarts = textPageStarts(in: document)
        let lines = textLines(onPageAt: caret.pageIndex, pageStarts: pageStarts)
        let activeOffset = activeCharacterOffset(
            extentOffset: state.extentOffset, anchorOffset: state.anchorOffset,
            totalLength: pageStarts.last ?? 0
        )
        guard let lineIndex = lineIndex(for: caret, fallbackOffset: caret.offset, in: lines),
              let character = lines[lineIndex].characters.min(by: {
                  abs($0.globalOffset - activeOffset) < abs($1.globalOffset - activeOffset)
              }) else {
            selectionEndpointOverlay?.isHidden = true
            return
        }

        let geometry = PDFPageDisplayGeometry(page: page, box: displayBox)
        let sideways = page.rotation % 180 != 0
        var center = caret.point
        var halfHeight = (sideways ? character.maxX - character.minX : character.height) / 2
        let isForward = state.extentOffset >= state.anchorOffset
        if let canonical = textCaret(
               atInsertionOffset: state.extentOffset,
               preferTrailingEdge: isForward,
               pageStarts: pageStarts
           ), sameVisualCaret(caret, canonical),
           abs(caret.point.x - canonical.point.x) < 0.01,
           abs(caret.point.y - canonical.point.y) < 0.01,
           let endpointCharacter = visibleTextCharacterWithLocation(
               near: activeOffset, preferPrevious: isForward, pageStarts: pageStarts
           ), endpointCharacter.pageIndex == caret.pageIndex {
            let bounds = endpointCharacter.bounds
            center = geometry.point(forPagePoint: NSPoint(
                x: isForward ? bounds.maxX : bounds.minX, y: bounds.midY
            ))
            halfHeight = bounds.height / 2
        }
        guard geometry.bounds.insetBy(dx: -1, dy: -1).contains(center) else {
            selectionEndpointOverlay?.isHidden = true
            return
        }
        let delta = sideways ? NSPoint(x: halfHeight, y: 0) : NSPoint(x: 0, y: halfHeight)
        let start = convert(geometry.pagePoint(forDisplayPoint: NSPoint(
            x: center.x - delta.x, y: center.y - delta.y
        )), from: page)
        let end = convert(geometry.pagePoint(forDisplayPoint: NSPoint(
            x: center.x + delta.x, y: center.y + delta.y
        )), from: page)
        let viewport = wordJumpViewport
        let strokeBounds = NSRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        ).insetBy(dx: -2, dy: -2)
        guard !viewport.isEmpty, halfHeight > 0, strokeBounds.intersects(viewport) else {
            selectionEndpointOverlay?.isHidden = true
            return
        }

        let overlay: SelectionEndpointOverlay
        if let existing = selectionEndpointOverlay {
            overlay = existing
        } else {
            overlay = SelectionEndpointOverlay(frame: viewport)
            selectionEndpointOverlay = overlay
            addSubview(overlay)
        }
        overlay.frame = viewport
        overlay.caretStart = overlay.convert(start, from: self)
        overlay.caretEnd = overlay.convert(end, from: self)
        overlay.isHidden = false
        overlay.needsDisplay = true
    }
}

final class SelectionEndpointOverlay: NSView {
    var caretStart = NSPoint.zero
    var caretEnd = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let stroke = NSBezierPath()
        stroke.move(to: caretStart)
        stroke.line(to: caretEnd)
        stroke.lineCapStyle = .round
        VellumColors.backgroundDeep.withAlphaComponent(0.9).setStroke()
        stroke.lineWidth = 3.5
        stroke.stroke()
        VellumColors.blue.setStroke()
        stroke.lineWidth = 1.5
        stroke.stroke()
    }
}

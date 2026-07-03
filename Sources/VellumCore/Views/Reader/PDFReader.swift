@preconcurrency import AppKit
import PDFKit
import SwiftUI

struct PDFReader: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
    let tabID: PDFTab.ID
    let document: PDFDocument
    let snapshot: ReaderSnapshot?
    let isActive: Bool

    func makeNSView(context: Context) -> PDFReaderContainerView {
        let container = PDFReaderContainerView()
        let view = container.pdfView
        view.appState = appState
        view.saveBeforeDismantle = { [weak appState, weak view] in
            guard view?.pendingActivationSnapshot == nil,
                  let snapshot = view?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }
        view.backgroundColor = TokyoNight.background
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        if isActive {
            view.restore(snapshot)
        } else {
            view.pendingActivationSnapshot = snapshot
        }
        appState.setActiveReaderController(view, for: tabID)
        if isActive, !appState.isOutlineVisible {
            if view.isAIInteractionActive {
                view.restoreAIFloatingOverlayPresentation()
            } else {
                view.focus()
            }
        }
        return container
    }

    func updateNSView(_ container: PDFReaderContainerView, context: Context) {
        let nsView = container.pdfView
        container.restoreOverlayHostIfNeeded()
        nsView.appState = appState
        nsView.saveBeforeDismantle = { [weak appState, weak nsView] in
            guard nsView?.pendingActivationSnapshot == nil,
                  let snapshot = nsView?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }

        if nsView.document !== document {
            nsView.document = document
            if isActive {
                nsView.restore(snapshot)
                nsView.pendingActivationSnapshot = nil
            } else {
                nsView.pendingActivationSnapshot = snapshot
            }
        } else if isActive, let pendingSnapshot = nsView.pendingActivationSnapshot {
            nsView.restore(pendingSnapshot)
            nsView.pendingActivationSnapshot = nil
        }

        appState.setActiveReaderController(nsView, for: tabID)
        if isActive, !appState.isOutlineVisible {
            DispatchQueue.main.async {
                if nsView.isAIInteractionActive {
                    nsView.restoreAIFloatingOverlayPresentationSoon()
                } else {
                    nsView.focus()
                }
            }
        }
    }

    static func dismantleNSView(_ container: PDFReaderContainerView, coordinator: ()) {
        container.pdfView.saveBeforeDismantle?()
    }
}

final class PDFReaderContainerView: NSView {
    let pdfView = VellumPDFView()
    private let overlayHostView = PDFReaderOverlayHostView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        pdfView.autoresizingMask = [.width, .height]
        overlayHostView.autoresizingMask = [.width, .height]

        addSubview(pdfView)
        addSubview(overlayHostView, positioned: .above, relativeTo: pdfView)
        restoreOverlayHostIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        pdfView.frame = bounds
        overlayHostView.frame = bounds
        restoreOverlayHostIfNeeded()
        pdfView.updateAIFloatingOverlayFrames()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restoreOverlayHostIfNeeded()
        pdfView.restoreAIFloatingOverlayPresentationSoon()
    }

    func restoreOverlayHostIfNeeded() {
        if pdfView.superview !== self {
            addSubview(pdfView, positioned: .below, relativeTo: overlayHostView)
        }
        if overlayHostView.superview !== self || subviews.last !== overlayHostView {
            addSubview(overlayHostView, positioned: .above, relativeTo: pdfView)
        }
        pdfView.aiFloatingOverlayHostView = overlayHostView
    }
}

private final class PDFReaderOverlayHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews.reversed() where !subview.isHidden && subview.alphaValue > 0.01 {
            let pointInSubview = convert(point, to: subview)
            if let hitView = subview.hitTest(pointInSubview) {
                return hitView
            }
        }

        return nil
    }
}

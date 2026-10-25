@preconcurrency import AppKit
import PDFKit
import SwiftUI

struct PDFReader: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
    let tabID: PDFTab.ID
    let document: PDFDocument
    let snapshot: ReaderSnapshot?
    let isActive: Bool

    func makeNSView(context: Context) -> PDFReaderContainer {
        let view = VellumPDFView()
        let container = PDFReaderContainer(reader: view)
        view.appState = appState
        configureSnapshotSaving(in: view)
        view.backgroundColor = VellumColors.panel
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        var pageBreakMargins = view.pageBreakMargins
        pageBreakMargins.left = 0
        pageBreakMargins.right = 0
        view.pageBreakMargins = pageBreakMargins
        view.document = document
        PDFAnnotationPersistence.state(for: document)?.onPrepareToClose = { [weak view] in
            view?.clearPDFReferences()
            view?.hideAIExplanationPopover()
        }
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

    func updateNSView(_ container: PDFReaderContainer, context: Context) {
        let nsView = container.reader
        nsView.appState = appState
        configureSnapshotSaving(in: nsView)

        if nsView.document !== document {
            nsView.clearPDFReferences()
            nsView.cancelWordJump()
            nsView.hideAIExplanationPopover()
            nsView.clearSuppressedHoverExplanation()
            nsView.cancelPageOverview()
            nsView.searchController?.clear()
            nsView.searchController = nil
            nsView.clearSelection()
            nsView.textSelectionNavigationState = nil
            nsView.jumpBackStack.removeAll()
            nsView.jumpForwardStack.removeAll()
            nsView.cancelPendingRestore()
            nsView.stopScrollAnimation()
            nsView.stopZoomState()
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

        if !isActive {
            nsView.cancelLinkPreview()
            nsView.cancelWordJump()
            nsView.cancelPendingRestore()
            nsView.stopScrollAnimation()
            nsView.stopZoomState()
            nsView.readerStateSaveWorkItem?.cancel()
        }

        PDFAnnotationPersistence.state(for: document)?.onPrepareToClose = { [weak nsView] in
            nsView?.clearPDFReferences()
            nsView?.hideAIExplanationPopover()
        }

        let becameActive = isActive && appState.activeReaderController !== nsView
        appState.setActiveReaderController(nsView, for: tabID)
        if becameActive {
            appState.focusActivatedReaderSoon(nsView)
        }
    }

    private func configureSnapshotSaving(in view: VellumPDFView) {
        view.saveBeforeDismantle = { [weak appState, weak view, weak document, tabID] in
            guard view?.pendingActivationSnapshot == nil,
                  let snapshot = view?.snapshot() else { return }
            // Publishing during SwiftUI teardown can re-enter its view graph.
            DispatchQueue.main.async { [weak appState, weak document] in
                guard let appState, let document,
                      appState.tabs.contains(where: { $0.id == tabID && $0.document === document }) else { return }
                appState.saveSnapshot(snapshot, for: tabID)
            }
        }
    }

    static func dismantleNSView(_ container: PDFReaderContainer, coordinator: ()) {
        let nsView = container.reader
        nsView.cancelWordJump()
        nsView.saveBeforeDismantle?()
        nsView.clearPDFReferences()
        nsView.hideAIExplanationPopover()
        nsView.cancelPageOverview()
        nsView.cancelPendingRestore()
        nsView.stopScrollAnimation()
        nsView.stopZoomState()
        nsView.readerStateSaveWorkItem?.cancel()
    }
}

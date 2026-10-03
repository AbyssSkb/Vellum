@preconcurrency import AppKit
import PDFKit
import SwiftUI

struct PDFReader: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
    let tabID: PDFTab.ID
    let document: PDFDocument
    let snapshot: ReaderSnapshot?
    let isActive: Bool

    func makeNSView(context: Context) -> VellumPDFView {
        let view = VellumPDFView()
        view.appState = appState
        view.saveBeforeDismantle = { [weak appState, weak view] in
            guard view?.pendingActivationSnapshot == nil,
                  let snapshot = view?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }
        view.backgroundColor = TokyoNight.panel
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        PDFAnnotationPersistence.state(for: document)?.onPrepareToClose = { [weak view] in
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
        return view
    }

    func updateNSView(_ nsView: VellumPDFView, context: Context) {
        nsView.appState = appState
        nsView.saveBeforeDismantle = { [weak appState, weak nsView] in
            guard nsView?.pendingActivationSnapshot == nil,
                  let snapshot = nsView?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }

        if nsView.document !== document {
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
            nsView.cancelPendingRestore()
            nsView.stopScrollAnimation()
            nsView.stopZoomState()
            nsView.readerStateSaveWorkItem?.cancel()
        }

        PDFAnnotationPersistence.state(for: document)?.onPrepareToClose = { [weak nsView] in
            nsView?.hideAIExplanationPopover()
        }

        let becameActive = isActive && appState.activeReaderController !== nsView
        appState.setActiveReaderController(nsView, for: tabID)
        if becameActive, !appState.isOutlineVisible {
            DispatchQueue.main.async { [weak appState, weak nsView] in
                guard let appState, let nsView,
                      appState.activeReaderController === nsView,
                      !appState.isOutlineVisible,
                      !appState.isTabSwitcherPresented,
                      !appState.isAIConversationHistoryPresented,
                      !appState.isAIExplanationHistoryPresented else { return }
                if nsView.isAIInteractionActive {
                    nsView.restoreAIFloatingOverlayPresentation()
                } else {
                    nsView.focus()
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: VellumPDFView, coordinator: ()) {
        nsView.saveBeforeDismantle?()
        nsView.hideAIExplanationPopover()
        nsView.cancelPageOverview()
        nsView.cancelPendingRestore()
        nsView.stopScrollAnimation()
        nsView.stopZoomState()
        nsView.readerStateSaveWorkItem?.cancel()
    }
}

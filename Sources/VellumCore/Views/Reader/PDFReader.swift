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
            view.focus()
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
                nsView.focus()
            }
        }
    }

    static func dismantleNSView(_ nsView: VellumPDFView, coordinator: ()) {
        nsView.saveBeforeDismantle?()
    }
}

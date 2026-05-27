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
            guard let snapshot = view?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }
        view.backgroundColor = TokyoNight.background
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        view.restore(snapshot)
        appState.setActivePDFView(view, for: tabID)
        if isActive, !appState.isOutlineVisible {
            view.focus()
        }
        return view
    }

    func updateNSView(_ nsView: VellumPDFView, context: Context) {
        nsView.appState = appState
        nsView.saveBeforeDismantle = { [weak appState, weak nsView] in
            guard let snapshot = nsView?.snapshot() else { return }
            appState?.saveSnapshot(snapshot, for: tabID)
        }

        if nsView.document !== document {
            nsView.document = document
            nsView.restore(snapshot)
        }

        appState.setActivePDFView(nsView, for: tabID)
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

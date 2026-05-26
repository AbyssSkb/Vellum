@preconcurrency import AppKit
import PDFKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var tabStore = TabStore()
    @Published var isOutlineVisible = false
    @Published var outlineFocusGeneration = 0
    @Published private(set) var selectedHighlightColor: HighlightColor = .yellow

    let documentCoordinator = DocumentCoordinator()

    weak var activePDFView: VellumPDFView?
    var keyMonitor: Any?
    var vimInput = VimInputController()
    let vimCommandDispatcher = VimCommandDispatcher()
    var heldKeyTimer: Timer?

    init() {
        installKeyMonitor()
        installOpenURLObserver()
    }

    var tabs: [PDFTab] {
        tabStore.tabs
    }

    var selectedTabID: PDFTab.ID? {
        tabStore.selectedTabID
    }

    var hasOpenDocuments: Bool {
        tabStore.hasOpenDocuments
    }

    var selectedTab: PDFTab? {
        tabStore.selectedTab
    }

    func toggleOutlineSidebar() {
        guard hasOpenDocuments else {
            isOutlineVisible = false
            return
        }

        isOutlineVisible.toggle()
        if isOutlineVisible {
            outlineFocusGeneration += 1
        } else {
            focusReaderSoon()
        }
    }

    func focusOutlineSidebar() {
        guard isOutlineVisible else { return }
        outlineFocusGeneration += 1
    }

    func jumpToOutlineDestination(_ destination: PDFDestination) {
        activePDFView?.vimGoToDestination(destination)
    }

    func selectHighlightColor(_ color: HighlightColor) {
        selectedHighlightColor = color
        focusActivePDFViewSoon()
    }

    func cycleHighlightColor(preserveFocus: Bool = false) {
        selectedHighlightColor = selectedHighlightColor.next
        if !preserveFocus {
            focusActivePDFViewSoon()
        }
    }

    func handleVimCommand(_ command: VimCommand) {
        vimCommandDispatcher.perform(command, on: self)
    }
}

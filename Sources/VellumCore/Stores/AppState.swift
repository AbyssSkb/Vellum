@preconcurrency import AppKit
import PDFKit
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published var tabStore = TabStore()
    @Published var isOutlineVisible = false
    @Published var isTabSwitcherPresented = false
    @Published var outlineFocusGeneration = 0
    @Published private(set) var selectedHighlightColor: HighlightColor

    let documentCoordinator = DocumentCoordinator()
    let keyboardController = KeyboardController()
    private var highlightColorPreferenceObserver: NSObjectProtocol?
    var didRestorePreviousTabs = false

    weak var activeReaderController: ReaderController?

    public init() {
        let rawHighlightColor = UserDefaults.standard.string(forKey: AppPreferenceKeys.defaultHighlightColor)
        selectedHighlightColor = rawHighlightColor.flatMap(HighlightColor.init(rawValue:)) ?? .yellow
        keyboardController.delegate = self
        highlightColorPreferenceObserver = NotificationCenter.default.addObserver(
            forName: VellumAppNotification.highlightColorPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?["color"] as? String,
                  let color = HighlightColor(rawValue: rawValue) else { return }
            Task { @MainActor [weak self] in
                self?.selectedHighlightColor = color
            }
        }
    }

    deinit {
        if let highlightColorPreferenceObserver {
            NotificationCenter.default.removeObserver(highlightColorPreferenceObserver)
        }
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
        activeReaderController?.vimGoToDestination(destination)
    }

    func selectHighlightColor(_ color: HighlightColor) {
        selectedHighlightColor = color
        UserDefaults.standard.set(color.rawValue, forKey: AppPreferenceKeys.defaultHighlightColor)
        focusActiveReaderSoon()
    }

    func cycleHighlightColor(preserveFocus: Bool = false) {
        selectedHighlightColor = selectedHighlightColor.next
        UserDefaults.standard.set(selectedHighlightColor.rawValue, forKey: AppPreferenceKeys.defaultHighlightColor)
        if !preserveFocus {
            focusActiveReaderSoon()
        }
    }

    func handleVimCommand(_ command: VimCommand) {
        vimCommandDispatcher.perform(command, on: self)
    }

    func showTabSwitcher() {
        guard hasOpenDocuments else { return }
        isTabSwitcherPresented = true
    }

    func hideTabSwitcher() {
        isTabSwitcherPresented = false
        focusActiveReaderSoon()
    }

    private let vimCommandDispatcher = VimCommandDispatcher()
}

extension AppState: KeyboardControllerDelegate {}

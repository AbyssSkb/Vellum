@preconcurrency import AppKit
import PDFKit
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published var tabStore = TabStore()
    @Published var isOutlineVisible = false
    @Published var isTabSwitcherPresented = false
    @Published var isAIConversationHistoryPresented = false
    @Published var isAIExplanationHistoryPresented = false
    @Published var aiConversationHistory: [AIConversationHistoryItem] = []
    @Published var aiExplanationHistory: [AIExplanationHistoryItem] = []
    @Published var outlineFocusGeneration = 0
    @Published private(set) var selectedHighlightColor: HighlightColor

    private var allAIConversationHistory: [AIConversationHistoryItem] = []
    private var allAIExplanationHistory: [AIExplanationHistoryItem] = []
    let pdfCoordinator = PDFCoordinator()
    let keyboardController = KeyboardController()
    private var highlightColorPreferenceObserver: NSObjectProtocol?
    private var appWillTerminateObserver: NSObjectProtocol?
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
        appWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveActiveReaderState()
            }
        }
    }

    deinit {
        if let highlightColorPreferenceObserver {
            NotificationCenter.default.removeObserver(highlightColorPreferenceObserver)
        }
        if let appWillTerminateObserver {
            NotificationCenter.default.removeObserver(appWillTerminateObserver)
        }
    }

    var tabs: [PDFTab] {
        tabStore.tabs
    }

    var selectedTabID: PDFTab.ID? {
        tabStore.selectedTabID
    }

    var hasOpenTabs: Bool {
        tabStore.hasOpenTabs
    }

    var selectedTab: PDFTab? {
        tabStore.selectedTab
    }

    func toggleOutlineSidebar() {
        guard hasOpenTabs else {
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
        guard hasOpenTabs else { return }
        isTabSwitcherPresented = true
    }

    func hideTabSwitcher() {
        isTabSwitcherPresented = false
        focusActiveReaderSoon()
    }

    func showAIConversationHistory() {
        aiConversationHistory = aiConversationHistoryItemsForActiveDocument()
        guard !aiConversationHistory.isEmpty else {
            activeReaderController?.showAINotification(AppUILanguage.saved().text(.noAIConversationsInFile))
            return
        }
        isAIConversationHistoryPresented = true
    }

    func hideAIConversationHistory() {
        isAIConversationHistoryPresented = false
        focusActiveReaderSoon()
    }

    func restoreAIConversation(_ item: AIConversationHistoryItem) {
        isAIConversationHistoryPresented = false
        activeReaderController?.restoreAIConversation(item)
    }

    func upsertAIConversationHistory(_ item: AIConversationHistoryItem) {
        if let index = allAIConversationHistory.firstIndex(where: { $0.id == item.id }) {
            allAIConversationHistory[index] = item
        } else {
            allAIConversationHistory.insert(item, at: 0)
        }
        allAIConversationHistory.sort { $0.updatedAt > $1.updatedAt }
        aiConversationHistory = aiConversationHistoryItemsForActiveDocument()
    }

    func showAIExplanationHistory() {
        aiExplanationHistory = aiExplanationHistoryItemsForActiveDocument()
        guard !aiExplanationHistory.isEmpty else {
            activeReaderController?.showAINotification(AppUILanguage.saved().text(.noAIExplanationsInFile))
            return
        }
        isAIExplanationHistoryPresented = true
    }

    func hideAIExplanationHistory() {
        isAIExplanationHistoryPresented = false
        focusActiveReaderSoon()
    }

    func restoreAIExplanation(_ item: AIExplanationHistoryItem) {
        isAIExplanationHistoryPresented = false
        activeReaderController?.restoreAIExplanation(item)
    }

    func upsertAIExplanationHistory(_ item: AIExplanationHistoryItem) {
        if let index = allAIExplanationHistory.firstIndex(where: { $0.id == item.id }) {
            allAIExplanationHistory[index] = item
        } else {
            allAIExplanationHistory.insert(item, at: 0)
        }
        allAIExplanationHistory.sort { $0.updatedAt > $1.updatedAt }
        aiExplanationHistory = aiExplanationHistoryItemsForActiveDocument()
    }

    private func aiConversationHistoryItemsForActiveDocument() -> [AIConversationHistoryItem] {
        let key = activeReaderController?.documentKey
        return allAIConversationHistory
            .filter { $0.context.documentKey == key }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func aiExplanationHistoryItemsForActiveDocument() -> [AIExplanationHistoryItem] {
        let key = activeReaderController?.documentKey
        let transientItems = allAIExplanationHistory.filter { $0.documentKey == key }
        let annotationItems = activeReaderController?.aiExplanationHistoryItems() ?? []
        var seen = Set<String>()

        return (transientItems + annotationItems)
            .filter { item in
                let dedupeKey = [
                    item.documentKey ?? "",
                    item.selectedText,
                    item.explanation,
                    item.pageNumbers.map(String.init).joined(separator: ",")
                ].joined(separator: "\u{1f}")
                return seen.insert(dedupeKey).inserted
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private let vimCommandDispatcher = VimCommandDispatcher()
}

extension AppState: KeyboardControllerDelegate {}

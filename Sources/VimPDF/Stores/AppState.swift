@preconcurrency import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var tabs: [PDFTab] = []
    @Published private(set) var selectedTabID: PDFTab.ID?
    @Published private(set) var isOutlineVisible = false
    @Published private(set) var outlineFocusGeneration = 0
    @Published private(set) var selectedHighlightColor: HighlightColor = .yellow

    private weak var activePDFView: VimPDFView?
    private var keyMonitor: Any?
    private var pendingKey: String?
    private var numericPrefix = ""
    private var heldKey: String?
    private var heldKeyTimer: Timer?
    private var closedPDFTabs: [PDFTab] = []

    init() {
        installKeyMonitor()
        installOpenURLObserver()
    }

    var hasOpenDocuments: Bool {
        !tabs.isEmpty
    }

    var selectedTab: PDFTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    func setActivePDFView(_ view: VimPDFView?, for tabID: PDFTab.ID) {
        guard tabID == selectedTabID else { return }
        activePDFView = view
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

    func selectTab(_ id: PDFTab.ID) {
        guard selectedTabID != id, tabs.contains(where: { $0.id == id }) else { return }
        saveActiveReaderState()
        selectedTabID = id
        focusActivePDFViewSoon()
    }

    func openPanel(mode: PDFOpenMode = .currentTab) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = mode == .newTabs
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            switch mode {
            case .currentTab:
                guard let url = panel.urls.first else { return }
                self?.openInCurrentTab(url: url)
            case .newTabs:
                self?.openInNewTabs(urls: panel.urls, reusingSelectedBlankTab: true)
            }
        }
    }

    func open(urls: [URL]) {
        openInNewTabs(urls: urls, reusingSelectedBlankTab: true)
    }

    func openInCurrentTab(url: URL) {
        saveActiveReaderState()

        guard let document = PDFDocument(url: url) else { return }
        let tab = PDFTab(url: url, document: document, snapshot: .initial)

        if let index = selectedIndex {
            tabs[index] = tab
        } else {
            tabs = [tab]
        }
        selectedTabID = tab.id
        activePDFView = nil

        focusActivePDFViewSoon()
    }

    func openInNewTabs(urls: [URL], reusingSelectedBlankTab: Bool) {
        saveActiveReaderState()

        var openedDocument = false
        for url in urls {
            guard let document = PDFDocument(url: url) else { continue }
            let tab = PDFTab(url: url, document: document, snapshot: .initial)

            tabs.append(tab)
            selectedTabID = tab.id
            openedDocument = true
        }

        if openedDocument {
            activePDFView = nil
            focusActivePDFViewSoon()
        }
    }

    func closeSelectedTab() {
        saveActiveReaderState()
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }

        rememberClosedPDFTab(tabs[index])
        tabs.remove(at: index)
        activePDFView = nil

        if tabs.isEmpty {
            self.selectedTabID = nil
            isOutlineVisible = false
        } else {
            self.selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        focusActivePDFViewSoon()
    }

    func restoreClosedPDFTab() {
        saveActiveReaderState()

        guard let tab = closedPDFTabs.popLast() else { return }
        tabs.append(tab)
        selectedTabID = tab.id
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    func selectNextTab() {
        guard let index = selectedIndex, !tabs.isEmpty else { return }
        selectTab(tabs[(index + 1) % tabs.count].id)
    }

    func selectPreviousTab() {
        guard let index = selectedIndex, !tabs.isEmpty else { return }
        selectTab(tabs[(index - 1 + tabs.count) % tabs.count].id)
    }

    func handleVimCommand(_ command: VimCommand) {
        switch command {
        case .open:
            openPanel(mode: .currentTab)
        case .openInNewTab:
            openPanel(mode: .newTabs)
        case .closeTab:
            closeSelectedTab()
        case .restoreClosedTab:
            restoreClosedPDFTab()
        case .nextTab:
            selectNextTab()
        case .previousTab:
            selectPreviousTab()
        case .scrollDown:
            activePDFView?.vimScroll(x: 0, y: -28)
        case .scrollUp:
            activePDFView?.vimScroll(x: 0, y: 28)
        case .largeScrollDown:
            activePDFView?.vimScroll(x: 0, y: -115)
        case .largeScrollUp:
            activePDFView?.vimScroll(x: 0, y: 115)
        case .scrollLeft:
            activePDFView?.vimScroll(x: -42, y: 0)
        case .scrollRight:
            activePDFView?.vimScroll(x: 42, y: 0)
        case .pageDown:
            activePDFView?.vimMoveByPage(1)
        case .pageUp:
            activePDFView?.vimMoveByPage(-1)
        case .firstPage:
            activePDFView?.vimGoToFirstPage()
        case .lastPage:
            activePDFView?.vimGoToLastPage()
        case .jumpToPage(let pageNumber):
            activePDFView?.vimGoToPage(pageNumber)
        case .jumpBack:
            activePDFView?.vimJumpBack()
        case .jumpForward:
            activePDFView?.vimJumpForward()
        case .toggleOutline:
            toggleOutlineSidebar()
        case .highlightSelection:
            activePDFView?.vimHighlightSelection(color: selectedHighlightColor.annotationColor)
        case .cycleHighlightColor:
            cycleHighlightColor()
        case .explainHighlightSelection:
            activePDFView?.vimExplainSelectedHighlight()
        case .zoomIn:
            activePDFView?.vimZoom(by: 1.04)
        case .zoomOut:
            activePDFView?.vimZoom(by: 1 / 1.04)
        case .zoomPageFit:
            activePDFView?.vimZoomToPageFit()
        case .zoomFit:
            activePDFView?.vimZoomToFit()
        }
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        selectedTab?.snapshot
    }

    func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: PDFTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].snapshot = snapshot
    }

    private var selectedIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    private func rememberClosedPDFTab(_ tab: PDFTab) {
        guard tab.document != nil else { return }
        closedPDFTabs.append(tab)

        if closedPDFTabs.count > 20 {
            closedPDFTabs.removeFirst(closedPDFTabs.count - 20)
        }
    }

    private func saveActiveReaderState() {
        guard let activePDFView,
              let selectedTabID,
              let snapshot = activePDFView.snapshot() else { return }
        saveSnapshot(snapshot, for: selectedTabID)
    }

    private func focusActivePDFViewSoon() {
        if isOutlineVisible {
            DispatchQueue.main.async { [weak self] in
                self?.outlineFocusGeneration += 1
            }
            return
        }
        focusReaderSoon()
    }

    private func focusReaderSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.activePDFView?.focus()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, NSApp.modalWindow == nil else { return event }

            if self.activePDFView?.handleAIKeyEvent(event) == true {
                return nil
            }

            if self.activePDFView?.handleTextSelectionKeyEvent(event) == true {
                self.stopHeldKeyTimer()
                self.numericPrefix = ""
                self.pendingKey = nil
                return nil
            }

            guard self.shouldRoute(event) else { return event }

            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func installOpenURLObserver() {
        OpenURLRelay.shared.activate { [weak self] urls in
            self?.open(urls: urls)
        }
    }

    private func shouldRoute(_ event: NSEvent) -> Bool {
        guard activePDFView?.isAIInteractionActive != true else { return false }
        guard let window = event.window, window.isVisible, !(window is NSPanel) else { return false }

        if let responder = window.firstResponder,
           responder is NSTextView || responder is NSTextField || responder is PDFOutlineKeyView || responderIsInsideAIExplanation(responder) {
            return false
        }

        return true
    }

    private func responderIsInsideAIExplanation(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }

        var current: NSView? = view
        while let candidate = current {
            if candidate is AIExplanationWebView {
                return true
            }
            current = candidate.superview
        }

        return false
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown, handleControlJump(event) {
            return true
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }

        if activePDFView?.handleTextSelectionKey(key, eventType: event.type) == true {
            stopHeldKeyTimer()
            numericPrefix = ""
            pendingKey = nil
            return true
        }

        switch event.type {
        case .keyDown:
            return handleKeyDown(key, isRepeat: event.isARepeat)
        case .keyUp:
            return handleKeyUp(key)
        default:
            return false
        }
    }

    private func handleControlJump(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control),
              event.modifierFlags.intersection([.command, .option]).isEmpty else { return false }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "o" || event.keyCode == 31 {
            stopHeldKeyTimer()
            numericPrefix = ""
            pendingKey = nil
            handleVimCommand(.jumpBack)
            return true
        }

        if key == "i" || event.keyCode == 34 {
            stopHeldKeyTimer()
            numericPrefix = ""
            pendingKey = nil
            handleVimCommand(.jumpForward)
            return true
        }

        return false
    }

    private func handleKeyDown(_ key: String, isRepeat: Bool) -> Bool {
        if handleUppercaseCommand(key) {
            return true
        }

        if activePDFView?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            stopHeldKeyTimer()
            numericPrefix = ""
            pendingKey = nil
            return true
        }

        if VimKeyMap.normalizedContinuousKey(key) == "d",
           activePDFView?.vimDeleteHighlightsForSelection() == true {
            stopHeldKeyTimer()
            heldKey = "d"
            numericPrefix = ""
            pendingKey = nil
            return true
        }

        guard VimKeyMap.isContinuousKey(key) else {
            if isRepeat {
                return VimKeyMap.isHandledKey(
                    key,
                    hasNavigableTextSelection: activePDFView?.hasNavigableTextSelection == true
                )
            }
            return handleKey(key)
        }

        let normalizedKey = VimKeyMap.normalizedContinuousKey(key)
        if heldKey == normalizedKey {
            return true
        }

        heldKey = normalizedKey
        performContinuousKey(heldKey)
        ensureHeldKeyTimer()
        return true
    }

    private func handleKeyUp(_ key: String) -> Bool {
        guard VimKeyMap.isContinuousKey(key),
              heldKey == VimKeyMap.normalizedContinuousKey(key) else { return false }
        stopHeldKeyTimer()
        return true
    }

    private func handleUppercaseCommand(_ key: String) -> Bool {
        switch key {
        case "G":
            if let pageNumber = consumeNumericPrefix() {
                handleVimCommand(.jumpToPage(pageNumber))
            } else {
                handleVimCommand(.lastPage)
            }
        case "H":
            numericPrefix = ""
            handleVimCommand(.previousTab)
        case "L":
            numericPrefix = ""
            handleVimCommand(.nextTab)
        case "X":
            numericPrefix = ""
            handleVimCommand(.restoreClosedTab)
        case "O":
            numericPrefix = ""
            handleVimCommand(.openInNewTab)
        default:
            return false
        }
        return true
    }

    func handleKey(_ key: String) -> Bool {
        if handleNumericPrefixKey(key) {
            return true
        }

        if pendingKey == "g" {
            pendingKey = nil
            numericPrefix = ""
            switch key {
            case "g":
                handleVimCommand(.firstPage)
            case "t":
                handleVimCommand(.nextTab)
            case "T":
                handleVimCommand(.previousTab)
            default:
                return false
            }
            return true
        }

        if activePDFView?.vimNavigateTextSelection(key) == true {
            numericPrefix = ""
            pendingKey = nil
            return true
        }

        switch key {
        case "g":
            numericPrefix = ""
            pendingKey = "g"
        case "\t", "t":
            numericPrefix = ""
            pendingKey = nil
            handleVimCommand(.toggleOutline)
        case "G":
            if let pageNumber = consumeNumericPrefix() {
                handleVimCommand(.jumpToPage(pageNumber))
            } else {
                handleVimCommand(.lastPage)
            }
        case "H":
            handleVimCommand(.previousTab)
        case "L":
            handleVimCommand(.nextTab)
        case "X":
            handleVimCommand(.restoreClosedTab)
        case "O":
            handleVimCommand(.openInNewTab)
        case "j":
            handleVimCommand(.scrollDown)
        case "k":
            handleVimCommand(.scrollUp)
        case "d":
            handleVimCommand(.largeScrollDown)
        case "u":
            handleVimCommand(.largeScrollUp)
        case "h":
            handleVimCommand(.scrollLeft)
        case "l":
            handleVimCommand(.scrollRight)
        case "a":
            handleVimCommand(.explainHighlightSelection)
        case "c":
            handleVimCommand(.cycleHighlightColor)
        case "m":
            handleVimCommand(.highlightSelection)
        case " ", "f":
            handleVimCommand(.pageDown)
        case "b":
            handleVimCommand(.pageUp)
        case "+", "=":
            handleVimCommand(.zoomIn)
        case "-":
            handleVimCommand(.zoomOut)
        case "0":
            handleVimCommand(.zoomPageFit)
        case "z":
            handleVimCommand(.zoomFit)
        case "o":
            handleVimCommand(.open)
        case "x":
            handleVimCommand(.closeTab)
        case "]":
            handleVimCommand(.nextTab)
        case "[":
            handleVimCommand(.previousTab)
        default:
            numericPrefix = ""
            guard let fallback = VimKeyMap.lowercaseFallback(for: key) else { return false }
            return handleKey(fallback)
        }
        return true
    }

    private func ensureHeldKeyTimer() {
        guard heldKeyTimer?.isValid != true else { return }

        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                guard self.heldKey != nil else {
                    self.stopHeldKeyTimer()
                    return
                }
                self.performContinuousKey(self.heldKey)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heldKeyTimer = timer
    }

    private func stopHeldKeyTimer() {
        heldKeyTimer?.invalidate()
        heldKeyTimer = nil
        heldKey = nil
    }

    private func handleNumericPrefixKey(_ key: String) -> Bool {
        switch key {
        case "1"..."9":
            numericPrefix.append(key)
            pendingKey = nil
            return true
        case "0" where !numericPrefix.isEmpty:
            numericPrefix.append(key)
            pendingKey = nil
            return true
        default:
            return false
        }
    }

    private func consumeNumericPrefix() -> Int? {
        defer { numericPrefix = "" }
        return Int(numericPrefix)
    }

    private func performContinuousKey(_ key: String?) {
        guard let key else { return }

        if activePDFView?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            return
        }

        switch key {
        case "j":
            handleVimCommand(.scrollDown)
        case "k":
            handleVimCommand(.scrollUp)
        case "d":
            handleVimCommand(.largeScrollDown)
        case "u":
            handleVimCommand(.largeScrollUp)
        case "h":
            handleVimCommand(.scrollLeft)
        case "l":
            handleVimCommand(.scrollRight)
        case "=":
            handleVimCommand(.zoomIn)
        case "-":
            handleVimCommand(.zoomOut)
        default:
            break
        }
    }

}

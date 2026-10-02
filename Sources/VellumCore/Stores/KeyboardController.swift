@preconcurrency import AppKit
import PDFKit

@MainActor
protocol KeyboardControllerDelegate: AnyObject {
    var activeReaderController: ReaderController? { get }
    var readerWindow: NSWindow? { get }
    func handleVimCommand(_ command: VimCommand)
    func open(urls: [URL])
}

@MainActor
final class KeyboardController {
    weak var delegate: KeyboardControllerDelegate? {
        didSet {
            guard delegate != nil, installsOpenURLObserver else { return }
            installOpenURLObserver()
        }
    }

    private let tabPageOverviewDelay: TimeInterval
    private let installsKeyMonitor: Bool
    private let installsOpenURLObserver: Bool
    private let notificationCenter: NotificationCenter
    private let openURLRelay: OpenURLRelay
    nonisolated(unsafe) private var keyMonitor: Any?
    private var vimInput = VimInputController()
    nonisolated(unsafe) private var heldKeyTimer: Timer?
    nonisolated(unsafe) private var tabPageOverviewTimer: Timer?
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private weak var inputWindow: NSWindow?
    private weak var inputResponder: NSResponder?
    private weak var inputReader: ReaderController?
    private var tabPageOverviewArmed = false
    private var tabPageOverviewActive = false

    init(
        tabPageOverviewDelay: TimeInterval = 0.35,
        installsKeyMonitor: Bool = true,
        installsOpenURLObserver: Bool = true,
        notificationCenter: NotificationCenter = .default,
        openURLRelay: OpenURLRelay = .shared
    ) {
        self.tabPageOverviewDelay = tabPageOverviewDelay
        self.installsKeyMonitor = installsKeyMonitor
        self.installsOpenURLObserver = installsOpenURLObserver
        self.notificationCenter = notificationCenter
        self.openURLRelay = openURLRelay
        installLifecycleObservers()
        if installsKeyMonitor {
            installKeyMonitor()
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        heldKeyTimer?.invalidate()
        tabPageOverviewTimer?.invalidate()
        lifecycleObservers.forEach(notificationCenter.removeObserver)
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if (vimInput.heldKey != nil || tabPageOverviewArmed || tabPageOverviewActive), !inputContextIsValid {
            cancelInput()
        }
        if event.type == .keyDown, handleControlJump(event) {
            return true
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            cancelInput()
            return false
        }

        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }
        if event.type == .keyDown, vimInput.heldKey == nil, !tabPageOverviewArmed, !tabPageOverviewActive {
            inputWindow = event.window
            inputResponder = event.window?.firstResponder
            inputReader = delegate?.activeReaderController
        }

        if handleTabPageOverviewKey(key, event: event) {
            return true
        }

        if tabPageOverviewActive {
            return true
        }

        if delegate?.activeReaderController?.handleTextSelectionKey(key, eventType: event.type) == true {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
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

    // MARK: - Monitor Installation

    private func installKeyMonitor() {
        guard installsKeyMonitor else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.routeKeyEvent(event) ? nil : event
        }
    }

    private func installLifecycleObservers() {
        lifecycleObservers = [NSApplication.willResignActiveNotification, NSWindow.didResignKeyNotification].map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelInput()
                }
            }
        }
    }

    private func installOpenURLObserver() {
        openURLRelay.activate { [weak self] urls in
            self?.delegate?.open(urls: urls)
        }
    }

    // MARK: - Routing

    func routeKeyEvent(_ event: NSEvent) -> Bool {
        guard NSApp?.modalWindow == nil,
              let window = event.window,
              window === delegate?.readerWindow,
              window.isVisible,
              !(window is NSPanel) else {
            cancelInput()
            return false
        }

        if let responder = window.firstResponder,
           responder is PDFOutlineKeyView
            || ((responder is NSTextView || responder is NSTextField) && !responderIsInsideAIOverlay(responder)) {
            cancelInput()
            return false
        }

        if delegate?.activeReaderController?.handleAIKeyEvent(event) == true {
            cancelInput()
            return true
        }

        guard delegate?.activeReaderController?.isAIInteractionActive != true,
              !responderIsInsideAIExplanation(window.firstResponder) else {
            cancelInput()
            return false
        }

        return handleKeyEvent(event)
    }

    private func responderIsInsideAIOverlay(_ responder: NSResponder) -> Bool {
        guard let reader = delegate?.activeReaderController as? VellumPDFView,
              let view = responder as? NSView else { return false }
        return [reader.aiInteraction.conversationOverlay, reader.aiInteraction.explanationOverlay]
            .compactMap { $0 }
            .contains { view === $0 || view.isDescendant(of: $0) }
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

    // MARK: - Key Handling

    private func handleControlJump(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control),
              event.modifierFlags.intersection([.command, .option]).isEmpty else { return false }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "o" || event.keyCode == 31 {
            cancelInput()
            delegate?.handleVimCommand(.jumpBack)
            return true
        }

        if key == "i" || event.keyCode == 34 {
            cancelInput()
            delegate?.handleVimCommand(.jumpForward)
            return true
        }

        return false
    }

    private func handleKeyDown(_ key: String, isRepeat: Bool) -> Bool {
        if delegate?.activeReaderController?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
            return true
        }

        let hasNavigableTextSelection = delegate?.activeReaderController?.hasNavigableTextSelection == true

        if hasNavigableTextSelection,
           key == "d",
           delegate?.activeReaderController?.vimDeleteHighlightsForSelection() == true {
            stopHeldKeyTimer()
            vimInput.beginHeldKey("d")
            vimInput.clearPendingInput()
            return true
        }

        let hasTextActionTarget = hasNavigableTextSelection
            || delegate?.activeReaderController?.hasSearchTextTarget == true

        return applyVimInputAction(
            vimInput.handleKeyDown(
                key,
                isRepeat: isRepeat,
                hasNavigableTextSelection: hasNavigableTextSelection,
                hasTextActionTarget: hasTextActionTarget
            )
        )
    }

    private func handleKeyUp(_ key: String) -> Bool {
        applyVimInputAction(vimInput.handleKeyUp(key))
    }

    // MARK: - Tab Page Overview

    private func handleTabPageOverviewKey(_ key: String, event: NSEvent) -> Bool {
        if key == "\t" {
            switch event.type {
            case .keyDown:
                return handleTabPageOverviewKeyDown(isRepeat: event.isARepeat)
            case .keyUp:
                return handleTabPageOverviewKeyUp()
            default:
                return false
            }
        }

        guard tabPageOverviewActive else { return false }
        guard let navigation = tabPageOverviewNavigation(for: key) else { return true }

        if event.type == .keyDown {
            _ = inputReader?.movePageOverview(navigation)
        }
        return event.type == .keyDown || event.type == .keyUp
    }

    private func handleTabPageOverviewKeyDown(isRepeat: Bool) -> Bool {
        guard !isRepeat else { return true }

        stopHeldKeyTimer()
        vimInput.clearPendingInput()

        guard !tabPageOverviewArmed, !tabPageOverviewActive else { return true }
        tabPageOverviewArmed = true

        let timer = Timer(timeInterval: tabPageOverviewDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activateTabPageOverview()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tabPageOverviewTimer = timer
        return true
    }

    private func handleTabPageOverviewKeyUp() -> Bool {
        tabPageOverviewTimer?.invalidate()
        tabPageOverviewTimer = nil

        if tabPageOverviewActive {
            tabPageOverviewActive = false
            tabPageOverviewArmed = false
            inputReader?.finishPageOverview()
            return true
        }

        if tabPageOverviewArmed {
            tabPageOverviewArmed = false
            delegate?.handleVimCommand(.toggleOutline)
            return true
        }

        return false
    }

    private func activateTabPageOverview() {
        tabPageOverviewTimer = nil
        guard tabPageOverviewArmed else { return }
        guard inputContextIsValid else {
            cancelInput()
            return
        }
        guard inputReader?.beginPageOverview() == true else {
            tabPageOverviewArmed = false
            return
        }
        tabPageOverviewActive = true
    }

    private func tabPageOverviewNavigation(for key: String) -> PageOverviewNavigation? {
        switch key.lowercased() {
        case "h":
            return .previous
        case "l":
            return .next
        case "k":
            return .previousRow
        case "j":
            return .nextRow
        default:
            return nil
        }
    }

    // MARK: - Held Key Timer

    private func ensureHeldKeyTimer() {
        guard heldKeyTimer?.isValid != true else { return }

        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                guard self.vimInput.heldKey != nil, self.inputContextIsValid else {
                    self.cancelInput()
                    return
                }
                self.performContinuousKey(self.vimInput.heldKey)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heldKeyTimer = timer
    }

    private func stopHeldKeyTimer() {
        heldKeyTimer?.invalidate()
        heldKeyTimer = nil
        vimInput.clearHeldKey()
    }

    private var inputContextIsValid: Bool {
        NSApp?.modalWindow == nil
            && delegate?.activeReaderController?.isAIInteractionActive != true
            && delegate?.activeReaderController === inputReader
            && (inputWindow == nil || inputWindow?.firstResponder === inputResponder)
    }

    func cancelInput() {
        stopHeldKeyTimer()
        vimInput.clearPendingInput()
        tabPageOverviewTimer?.invalidate()
        tabPageOverviewTimer = nil
        tabPageOverviewArmed = false
        if tabPageOverviewActive {
            tabPageOverviewActive = false
            inputReader?.cancelPageOverview()
        }
        inputWindow = nil
        inputResponder = nil
        inputReader = nil
    }

    // MARK: - Vim Input Dispatch

    private func performContinuousKey(_ key: String?) {
        guard let key else { return }

        if delegate?.activeReaderController?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            return
        }

        if let command = VimKeyMap.continuousCommand(for: key) {
            delegate?.handleVimCommand(command)
        }
    }

    private func applyVimInputAction(_ action: VimInputAction) -> Bool {
        switch action {
        case .ignored:
            return false
        case .handled:
            return true
        case .command(let command):
            delegate?.handleVimCommand(command)
            return true
        case .continuousKey(let key):
            performContinuousKey(key)
            ensureHeldKeyTimer()
            return true
        case .stopContinuousKey:
            stopHeldKeyTimer()
            return true
        }
    }
}

@preconcurrency import AppKit
import PDFKit

@MainActor
protocol KeyboardControllerDelegate: AnyObject {
    var activeReaderController: ReaderController? { get }
    func handleVimCommand(_ command: VimCommand)
    func open(urls: [URL])
}

@MainActor
final class KeyboardController {
    weak var delegate: KeyboardControllerDelegate?

    private let tabPageOverviewDelay: TimeInterval
    private let installsKeyMonitor: Bool
    private let installsOpenURLObserver: Bool
    nonisolated(unsafe) private var keyMonitor: Any?
    private var vimInput = VimInputController()
    nonisolated(unsafe) private var heldKeyTimer: Timer?
    nonisolated(unsafe) private var tabPageOverviewTimer: Timer?
    private var tabPageOverviewArmed = false
    private var tabPageOverviewActive = false

    init(
        tabPageOverviewDelay: TimeInterval = 0.35,
        installsKeyMonitor: Bool = true,
        installsOpenURLObserver: Bool = true
    ) {
        self.tabPageOverviewDelay = tabPageOverviewDelay
        self.installsKeyMonitor = installsKeyMonitor
        self.installsOpenURLObserver = installsOpenURLObserver
        if installsKeyMonitor {
            installKeyMonitor()
        }
        if installsOpenURLObserver {
            installOpenURLObserver()
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        heldKeyTimer?.invalidate()
        tabPageOverviewTimer?.invalidate()
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown, handleControlJump(event) {
            return true
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }

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
            guard let self, NSApp.modalWindow == nil else { return event }

            if self.delegate?.activeReaderController?.handleAIKeyEvent(event) == true {
                return nil
            }

            guard self.shouldRoute(event) else { return event }

            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func installOpenURLObserver() {
        OpenURLRelay.shared.activate { [weak self] urls in
            self?.delegate?.open(urls: urls)
        }
    }

    // MARK: - Routing

    private func shouldRoute(_ event: NSEvent) -> Bool {
        guard delegate?.activeReaderController?.isAIInteractionActive != true else { return false }
        guard let window = event.window, window.isVisible, !(window is NSPanel) else { return false }

        if let responder = window.firstResponder,
           responder is NSTextView || responder is NSTextField || responder is DocumentOutlineKeyView || responderIsInsideAIExplanation(responder) {
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

    // MARK: - Key Handling

    private func handleControlJump(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control),
              event.modifierFlags.intersection([.command, .option]).isEmpty else { return false }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "o" || event.keyCode == 31 {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
            delegate?.handleVimCommand(.jumpBack)
            return true
        }

        if key == "i" || event.keyCode == 34 {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
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
            _ = delegate?.activeReaderController?.movePageOverview(navigation)
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
            delegate?.activeReaderController?.finishPageOverview()
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
        guard delegate?.activeReaderController?.beginPageOverview() == true else {
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
                guard self.vimInput.heldKey != nil else {
                    self.stopHeldKeyTimer()
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

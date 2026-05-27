import AppKit

extension AppState {
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        keyboardController.handleKeyEvent(event)
    }
}

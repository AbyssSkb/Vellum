import AppKit

extension AppState {
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        keyboardController.routeKeyEvent(event)
    }
}

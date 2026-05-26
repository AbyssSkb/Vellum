import AppKit

enum AIKeyEventRouter {
    enum Action: Equatable {
        case none
        case dismissHover
        case startContinuousScroll(directionKey: String)
        case stopContinuousScroll
        case forwardToWebView(key: String)
        case consume
    }

    static let consumedKeys: Set<String> = ["j", "k", "m", "c", "\u{1b}"]

    static func action(
        key: String,
        eventType: NSEvent.EventType,
        hasHoveredExplanation: Bool,
        continuousScrollKey: String?
    ) -> Action {
        switch eventType {
        case .keyDown:
            if key == "\u{1b}", hasHoveredExplanation {
                return .dismissHover
            }

            if key == "j" || key == "k" {
                return .startContinuousScroll(directionKey: key)
            }

            if consumedKeys.contains(key) {
                return .forwardToWebView(key: key)
            }
            return .none
        case .keyUp:
            if key == "j" || key == "k" {
                if continuousScrollKey == key {
                    return .stopContinuousScroll
                }
                return .consume
            }

            return consumedKeys.contains(key) ? .consume : .none
        default:
            return .none
        }
    }
}

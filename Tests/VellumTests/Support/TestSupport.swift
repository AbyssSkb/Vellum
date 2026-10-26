@preconcurrency import AppKit
import Foundation
import Testing
@testable import VellumCore

struct TestPreferences {
    let suiteName = "VellumTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
func makeTestAppState(defaults: UserDefaults) -> AppState {
    AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
        installsKeyMonitor: false, installsOpenURLObserver: false,
        notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
    ))
}

@MainActor
func waitForTestCondition(
    _ description: String,
    timeout: Duration = .seconds(5),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
        // The test host's CFRunLoop does not dispatch AppKit visibility events.
        if let application = NSApp {
            while let event = application.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                application.sendEvent(event)
            }
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), Comment(rawValue: description))
}

@MainActor
func nextTestMainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

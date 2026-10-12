import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("AI localization")
struct AILocalizationTests {
    @Test
    func localErrorsUseTheChosenLanguageAndKeepServerMessages() {
        let errors: [AIExplanationError] = [
            .invalidBaseURL, .missingModel, .missingAPIKey, .missingCodexExecutable,
            .noSelection, .noHighlightedText, .emptyResponse, .responseTruncated,
            .streamEndedPrematurely
        ]
        for error in errors {
            #expect(error.message(language: .english) != error.message(language: .chinese))
            #expect(!error.message(language: .english).isEmpty)
            #expect(!error.message(language: .chinese).isEmpty)
        }
        #expect(AIExplanationError.server("Provider detail").message(language: .chinese) == "Provider detail")
    }

    @Test
    @MainActor
    func hostedLanguageChangesWithoutRecreatingContentState() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set(AppUILanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        var records: [(AppUILanguage, UUID)] = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let hosting = NSHostingView(rootView: AppLanguageObservedView(content: LanguageProbe { records.append(($0, $1)) }).defaultAppStorage(defaults))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await waitForTestCondition("Hosted content uses the initial app language") {
            hosting.layoutSubtreeIfNeeded()
            return records.last?.0 == .english
        }
        let first = try #require(records.last)
        #expect(first.0 == .english)

        defaults.set(AppUILanguage.chinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        try await waitForTestCondition("Hosted content observes the new app language") {
            hosting.layoutSubtreeIfNeeded()
            return records.last?.0 == .chinese
        }
        let last = try #require(records.last)
        #expect(last.0 == .chinese)
        #expect(last.1 == first.1)
    }
}

private struct LanguageProbe: View {
    @Environment(\.appUILanguage) private var language
    @State private var contentIdentity = UUID()
    let record: (AppUILanguage, UUID) -> Void

    var body: some View {
        LanguageProbeRepresentable(language: language, contentIdentity: contentIdentity, record: record)
    }
}

private struct LanguageProbeRepresentable: NSViewRepresentable {
    let language: AppUILanguage
    let contentIdentity: UUID
    let record: (AppUILanguage, UUID) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        record(language, contentIdentity)
    }
}

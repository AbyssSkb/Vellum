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
        #expect(AIExplanationError.missingModel.message(language: .english) == "Enter an AI model name in Settings.")
        #expect(AIExplanationError.missingModel.message(language: .chinese) == "AI 模型名称为空，请先在设置里填写模型名称。")
        #expect(AIExplanationError.server("Provider detail").message(language: .chinese) == "Provider detail")
        #expect(AppUILanguage.english.text(.outlinePage(3)) == "Page 3")
        #expect(AppUILanguage.chinese.text(.outlinePage(3)) == "第 3 页")
        #expect(AppUILanguage.chinese.text(.sidebarOpen) == "已展开")
    }

    @Test
    @MainActor
    func hostedLanguageChangesWithoutRecreatingContentState() async throws {
        _ = NSApplication.shared
        let suite = "VellumTests.AILanguage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppUILanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        var records: [(AppUILanguage, UUID)] = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: AppLanguageObservedView(content: LanguageProbe { records.append(($0, $1)) }).defaultAppStorage(defaults))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let initialDeadline = Date().addingTimeInterval(5)
        while records.last?.0 != .english, Date() < initialDeadline {
            try await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
        }
        let first = try #require(records.last)
        #expect(first.0 == .english)

        defaults.set(AppUILanguage.chinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        let updateDeadline = Date().addingTimeInterval(5)
        while records.last?.0 != .chinese, Date() < updateDeadline {
            try await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
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

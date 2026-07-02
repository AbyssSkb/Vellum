import SwiftUI


struct AIExplanationPopoverView: View {
    @Environment(\.appUILanguage) private var language
    @ObservedObject var model: AIExplanationPopoverModel
    let kind: AIExplanationPopoverKind
    let onDismiss: () -> Void
    let onHighlight: () -> Void
    let onCycleColor: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let onWebViewReady: (AIExplanationWebView) -> Void

    var body: some View {
        MarkdownWebView(
            markdown: renderedMarkdown,
            onDismiss: onDismiss,
            onHighlight: onHighlight,
            onCycleColor: onCycleColor,
            onContentHeightChange: onContentHeightChange,
            focusWhenReady: kind.shouldFocusWebView,
            autoScrollOnUpdate: kind.autoScrollOnUpdate,
            pronunciationSpeechText: model.pronunciationSpeechText,
            autoPronunciationLanguageCode: autoPronunciationLanguageCode,
            speakAmericanButtonTitle: language.text(.speakAmericanPronunciation),
            speakBritishButtonTitle: language.text(.speakBritishPronunciation),
            onReady: onWebViewReady
        )
        .frame(width: model.preferredSize.width, height: model.preferredSize.height)
        .background(TokyoNight.panelElevatedColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var renderedMarkdown: String {
        let trimmed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return model.text }
        return loadingMarkdown
    }

    private var loadingMarkdown: String {
        let configuration = try? AIConfiguration.current(profile: .explanation)
        let provider = Self.providerDisplayName(profile: .explanation)
        let modelName = configuration?.model.nilIfEmpty
            ?? (configuration?.providerFormat == .codexCLI ? language.text(.useCodexDefault) : language.text(.notSet))
        let payload = [
            "provider": provider,
            "model": modelName
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "vellum-loading:{}"
        }
        return "vellum-loading:\(json)"
    }

    private static func providerDisplayName(profile: AIConfigurationProfile) -> String {
        let providerID = UserDefaults.standard.string(forKey: profile.providerIDKey)
            ?? AIProviderPreset.presets.first?.id
            ?? AIProviderPreset.customID
        return AIProviderPreset.preset(for: providerID).name
    }

    private var autoPronunciationLanguageCode: String? {
        guard kind != .hover,
              !model.isStreaming,
              AppPreferences.automaticallyPronouncesAIExplanation() else {
            return nil
        }

        return AppPreferences.aiExplanationAutoPronunciationAccent().languageCode
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let onDismiss: () -> Void
    let onHighlight: () -> Void
    let onCycleColor: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let focusWhenReady: Bool
    let autoScrollOnUpdate: Bool
    let pronunciationSpeechText: String?
    let autoPronunciationLanguageCode: String?
    let speakAmericanButtonTitle: String
    let speakBritishButtonTitle: String
    let onReady: (AIExplanationWebView) -> Void

    func makeNSView(context: Context) -> AIExplanationWebView {
        let webView = AIExplanationWebView()
        webView.onDismiss = onDismiss
        webView.onHighlight = onHighlight
        webView.onCycleColor = onCycleColor
        webView.onContentHeightChange = onContentHeightChange
        webView.shouldFocusWhenReady = focusWhenReady
        webView.autoScrollOnUpdate = autoScrollOnUpdate
        webView.pronunciationSpeechText = pronunciationSpeechText
        webView.autoPronunciationLanguageCode = autoPronunciationLanguageCode
        webView.speakAmericanButtonTitle = speakAmericanButtonTitle
        webView.speakBritishButtonTitle = speakBritishButtonTitle
        onReady(webView)
        webView.render(markdown)
        return webView
    }

    func updateNSView(_ webView: AIExplanationWebView, context: Context) {
        webView.onDismiss = onDismiss
        webView.onHighlight = onHighlight
        webView.onCycleColor = onCycleColor
        webView.onContentHeightChange = onContentHeightChange
        webView.shouldFocusWhenReady = focusWhenReady
        webView.autoScrollOnUpdate = autoScrollOnUpdate
        webView.pronunciationSpeechText = pronunciationSpeechText
        webView.autoPronunciationLanguageCode = autoPronunciationLanguageCode
        webView.speakAmericanButtonTitle = speakAmericanButtonTitle
        webView.speakBritishButtonTitle = speakBritishButtonTitle
        onReady(webView)
        webView.render(markdown)

        guard focusWhenReady else { return }

        DispatchQueue.main.async { [weak webView] in
            guard let webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
    }
}

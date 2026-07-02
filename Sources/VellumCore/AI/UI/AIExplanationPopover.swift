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
            speakAmericanButtonTitle: language.text(.speakAmericanPronunciation),
            speakBritishButtonTitle: language.text(.speakBritishPronunciation),
            onReady: onWebViewReady
        )
        .frame(width: model.preferredSize.width, height: model.preferredSize.height)
        .background(TokyoNight.panelElevatedColor)
    }

    private var renderedMarkdown: String {
        let trimmed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return model.text }
        return loadingMarkdown
    }

    private var loadingMarkdown: String {
        let configuration = try? AIConfiguration.current(profile: .explanation)
        let provider = configuration?.providerFormat.title ?? language.text(.notSet)
        let modelName = configuration?.model.nilIfEmpty
            ?? (configuration?.providerFormat == .codexCLI ? language.text(.useCodexDefault) : language.text(.notSet))
        return """
        **\(language.text(.aiExplanation))**

        - \(language.text(.aiExplanationLoadingStage)): \(language.text(.aiExplanationLoadingRequesting))
        - \(language.text(.provider)): \(provider)
        - \(language.text(.model)): \(modelName)
        """
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

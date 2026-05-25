@preconcurrency import AppKit
import SwiftUI

enum AIExplanationPopoverMetrics {
    static let width: CGFloat = 520
    static let hoverMinimumHeight: CGFloat = 56
    static let minimumHeight: CGFloat = 124
    static let streamingMinimumHeight: CGFloat = 56
    static let maximumHeight: CGFloat = 420
    static let compactInitialHeight: CGFloat = 148
    static let standardInitialHeight: CGFloat = 260

    static func estimatedHeight(for markdown: String) -> CGFloat {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return minimumHeight }

        let lines = trimmed.components(separatedBy: .newlines)
        var headingCount = 0
        var paragraphCount = 0
        var listItemCount = 0
        var blankLineCount = 0
        let estimatedLineCount = lines.reduce(0) { partialResult, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                blankLineCount += 1
                return partialResult
            }

            if line.hasPrefix("#") {
                headingCount += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                listItemCount += 1
            } else {
                paragraphCount += 1
            }

            let characterCount = max(1, line.count)
            return partialResult + max(1, Int(ceil(Double(characterCount) / 56.0)))
        }

        let contentHeight = CGFloat(estimatedLineCount) * 21
            + CGFloat(headingCount) * 12
            + CGFloat(paragraphCount) * 6
            + CGFloat(listItemCount) * 3
            + CGFloat(blankLineCount) * 4
            + 46
        return min(maximumHeight, max(minimumHeight, contentHeight))
    }

    static func estimatedHoverHeight(for markdown: String) -> CGFloat {
        let lines = markdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return hoverMinimumHeight }

        let contentHeight = lines.enumerated().reduce(CGFloat(36)) { partialResult, element in
            let (index, line) = element
            let estimatedLineCount = max(1, Int(ceil(Double(max(1, line.count)) / 58.0)))
            let lineHeight: CGFloat = line.hasPrefix("#") ? 22 : 20
            let spacing: CGFloat = index == lines.count - 1 ? 0 : 9
            return partialResult + CGFloat(estimatedLineCount) * lineHeight + spacing
        }

        return min(maximumHeight, max(hoverMinimumHeight, ceil(contentHeight)))
    }
}

@MainActor
final class AIExplanationPopoverModel: ObservableObject {
    @Published var title: String
    @Published var text: String
    @Published var isStreaming: Bool
    @Published private(set) var preferredHeight: CGFloat
    let maximumHeight: CGFloat

    init(
        title: String,
        text: String = "",
        isStreaming: Bool = false,
        initialHeight: CGFloat = AIExplanationPopoverMetrics.standardInitialHeight,
        maximumHeight: CGFloat = AIExplanationPopoverMetrics.maximumHeight
    ) {
        self.title = title
        self.text = text
        self.isStreaming = isStreaming
        self.preferredHeight = initialHeight
        self.maximumHeight = maximumHeight
    }

    func append(_ chunk: String) {
        if text == "..." {
            text = ""
        }
        text += chunk
    }

    var preferredSize: NSSize {
        NSSize(width: AIExplanationPopoverMetrics.width, height: preferredHeight)
    }

    @discardableResult
    func updateContentHeight(
        _ contentHeight: CGFloat,
        minimumHeight: CGFloat = AIExplanationPopoverMetrics.minimumHeight
    ) -> Bool {
        let clampedHeight = min(
            maximumHeight,
            max(minimumHeight, ceil(contentHeight))
        )

        guard abs(preferredHeight - clampedHeight) > 8 else { return false }
        preferredHeight = clampedHeight
        return true
    }
}

struct AIExplanationPopoverView: View {
    @ObservedObject var model: AIExplanationPopoverModel
    let kind: AIExplanationPopoverKind
    let onDismiss: () -> Void
    let onHighlight: () -> Void
    let onCycleColor: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let onWebViewReady: (AIExplanationWebView) -> Void

    var body: some View {
        MarkdownWebView(
            markdown: model.text.isEmpty ? "..." : model.text,
            onDismiss: onDismiss,
            onHighlight: onHighlight,
            onCycleColor: onCycleColor,
            onContentHeightChange: onContentHeightChange,
            focusWhenReady: kind.shouldFocusWebView,
            autoScrollOnUpdate: kind.autoScrollOnUpdate,
            onReady: onWebViewReady
        )
        .frame(width: model.preferredSize.width, height: model.preferredSize.height)
        .background(TokyoNight.panelElevatedColor)
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
    let onReady: (AIExplanationWebView) -> Void

    func makeNSView(context: Context) -> AIExplanationWebView {
        let webView = AIExplanationWebView()
        webView.onDismiss = onDismiss
        webView.onHighlight = onHighlight
        webView.onCycleColor = onCycleColor
        webView.onContentHeightChange = onContentHeightChange
        webView.shouldFocusWhenReady = focusWhenReady
        webView.autoScrollOnUpdate = autoScrollOnUpdate
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
        onReady(webView)
        webView.render(markdown)

        guard focusWhenReady else { return }

        DispatchQueue.main.async { [weak webView] in
            guard let webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
    }
}

enum AIExplanationPopoverKind {
    case hover
    case message
    case streaming

    var behavior: NSPopover.Behavior {
        switch self {
        case .hover:
            return .applicationDefined
        case .message, .streaming:
            return .transient
        }
    }

    var animates: Bool {
        switch self {
        case .hover, .message, .streaming:
            return true
        }
    }

    var shouldFocusWebView: Bool {
        switch self {
        case .hover:
            return false
        case .message, .streaming:
            return true
        }
    }

    var allowsDynamicHeight: Bool {
        switch self {
        case .hover, .message, .streaming:
            return true
        }
    }

    var autoScrollOnUpdate: Bool {
        switch self {
        case .hover, .message, .streaming:
            return false
        }
    }
}

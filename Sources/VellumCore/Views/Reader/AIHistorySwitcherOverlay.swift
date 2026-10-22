@preconcurrency import AppKit
import SwiftUI

struct AIConversationHistorySwitcherOverlay: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AIHistorySwitcherOverlay(
            mode: .conversation,
            items: appState.aiConversationHistory.map(AIHistorySwitcherItem.init),
            onDismiss: appState.hideAIConversationHistory,
            onOpen: { item in
                guard let historyItem = appState.aiConversationHistory.first(where: { $0.id == item.id }) else { return }
                appState.restoreAIConversation(historyItem)
            }
        )
    }
}

struct AIExplanationHistorySwitcherOverlay: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AIHistorySwitcherOverlay(
            mode: .explanation,
            items: appState.aiExplanationHistory.map(AIHistorySwitcherItem.init),
            onDismiss: appState.hideAIExplanationHistory,
            onOpen: { item in
                guard let historyItem = appState.aiExplanationHistory.first(where: { $0.id == item.id }) else { return }
                appState.restoreAIExplanation(historyItem)
            }
        )
    }
}

struct HighlightSwitcherOverlay: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AIHistorySwitcherOverlay(
            mode: .highlights,
            items: appState.highlightItems.map { AIHistorySwitcherItem($0, language: language) },
            onDismiss: appState.hideHighlights,
            onOpen: { item in
                guard let highlight = appState.highlightItems.first(where: { $0.id == item.id }) else { return }
                appState.openHighlight(highlight)
            }
        )
    }
}

private struct AIHistorySwitcherOverlay: View {
    enum Mode {
        case conversation
        case explanation
        case highlights

        var systemImage: String {
            switch self {
            case .conversation: return "bubble.left.and.bubble.right"
            case .explanation: return "sparkles"
            case .highlights: return "highlighter"
            }
        }

        func title(in language: AppUILanguage) -> String {
            switch self {
            case .conversation: return language.text(.aiConversationHistory)
            case .explanation: return language.text(.aiExplanationHistory)
            case .highlights: return language.text(.highlights)
            }
        }

        func placeholder(in language: AppUILanguage) -> String {
            switch self {
            case .conversation: return language.text(.searchAIConversations)
            case .explanation: return language.text(.searchAIExplanations)
            case .highlights: return language.text(.searchHighlights)
            }
        }

        func emptyText(in language: AppUILanguage, hasItems: Bool) -> String {
            switch self {
            case .conversation: return language.text(.noMatchingAIConversations)
            case .explanation: return language.text(.noMatchingAIExplanations)
            case .highlights: return language.text(hasItems ? .noMatchingHighlights : .noHighlightsInFile)
            }
        }
    }

    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    let mode: Mode
    let items: [AIHistorySwitcherItem]
    let onDismiss: () -> Void
    let onOpen: (AIHistorySwitcherItem) -> Void
    @State private var query = ""
    @State private var selectedIndex = 0

    private var matches: [AIHistorySwitcherItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }

        return items.filter { item in
            item.searchableText.localizedCaseInsensitiveContains(term)
        }
    }

    private var listHeight: CGFloat {
        let visibleRows = matches.isEmpty ? 1 : min(matches.count, 6)
        return CGFloat(visibleRows) * AIHistorySwitcherRow.metricsHeight + CGFloat(visibleRows - 1) * 2 + 12
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(VellumColors.backgroundDeepColor.opacity(0.48))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                searchHeader

                Rectangle()
                    .fill(VellumColors.foregroundColor.opacity(0.06))
                    .frame(height: 1)

                historyList
            }
            .frame(maxWidth: 620)
            .background {
                ZStack {
                    AIHistoryVisualEffectBackground()
                    VellumColors.panelColor.opacity(0.98)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(VellumColors.foregroundColor.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: matches.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedIndex = 0
                return
            }
            selectedIndex = min(selectedIndex, ids.count - 1)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VellumColors.mutedColor)
                .frame(width: 24, height: 24)

            ListSearchField(
                text: $query,
                placeholder: mode.placeholder(in: language),
                font: .systemFont(ofSize: 14, weight: .medium),
                canFocus: { [weak appState] in
                    appState?.isAIConversationHistoryPresented == true || appState?.isAIExplanationHistoryPresented == true
                        || appState?.isHighlightsPresented == true
                },
                onMoveUp: { moveSelection(.up) },
                onMoveDown: { moveSelection(.down) },
                onCommit: openSelectedMatch,
                onCancel: onDismiss
            )
            .frame(height: 30)

            matchCount
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(VellumColors.backgroundColor)
    }

    private var matchCount: some View {
        Text("\(matches.count)")
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(matches.isEmpty ? VellumColors.redColor : VellumColors.mutedColor)
            .frame(minWidth: 24)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if matches.isEmpty {
                        emptyRow
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                            AIHistorySwitcherRow(
                                item: item,
                                isSelected: index == selectedIndex
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onOpen(item)
                            }
                        }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.hidden)
            .frame(height: listHeight)
            .background(VellumColors.panelColor)
            .onChange(of: selectedItemIDForScroll) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VellumColors.mutedColor)
                .frame(width: 22)

            Text(mode.emptyText(in: language, hasItems: !items.isEmpty))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VellumColors.mutedColor)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: AIHistorySwitcherRow.metricsHeight)
    }

    private var selectedItemIDForScroll: AIHistorySwitcherItem.ID? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex].id
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !matches.isEmpty else { return }

        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(matches.count - 1, selectedIndex + 1)
        default:
            break
        }
    }

    private func openSelectedMatch() {
        guard matches.indices.contains(selectedIndex) else { return }
        onOpen(matches[selectedIndex])
    }
}

private struct AIHistorySwitcherItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let preview: String
    let searchableText: String

    init(_ item: AIConversationHistoryItem) {
        id = item.id
        title = item.selectedText.aiHistorySwitcherTitle
        preview = item.messages.last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.content
            ?? item.selectedText
        searchableText = item.searchableText
    }

    init(_ item: AIExplanationHistoryItem) {
        id = item.id
        title = item.selectedText.aiHistorySwitcherTitle
        preview = item.explanation
        searchableText = item.searchableText
    }

    @MainActor
    init(_ item: HighlightListItem, language: AppUILanguage) {
        id = item.id
        title = item.text.isEmpty ? language.text(.highlightWithoutText) : item.text.aiHistorySwitcherTitle
        preview = item.pageNumbers.map { language.text(.outlinePage($0)) }.joined(separator: " · ")
        searchableText = item.searchableText
    }
}

private extension String {
    var aiHistorySwitcherTitle: String {
        let title = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard title.count > 52 else { return title }
        return String(title.prefix(52)) + "..."
    }
}

private struct AIHistorySwitcherRow: View {
    static let metricsHeight: CGFloat = 52
    let item: AIHistorySwitcherItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(VellumColors.foregroundColor)
                    .lineLimit(1)

                Text(item.preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(VellumColors.mutedColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.metricsHeight)
        .background(
            isSelected ? VellumColors.selectionColor.opacity(0.85) : isHovered ? VellumColors.panelElevatedColor.opacity(0.35) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(VellumColors.blueColor)
                    .frame(width: 2, height: 12)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovered = $0 }
    }
}

private struct AIHistoryVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .withinWindow
        nsView.state = .active
        nsView.isEmphasized = false
    }
}

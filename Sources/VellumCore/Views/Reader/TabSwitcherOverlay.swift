import SwiftUI

struct TabSwitcherOverlay: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0

    private var matches: [PDFTab] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return appState.tabs }

        return appState.tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(term)
                || (tab.url?.lastPathComponent.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private var listHeight: CGFloat {
        let visibleRows = matches.isEmpty ? 1 : min(matches.count, 6)
        return CGFloat(visibleRows) * TabSwitcherRow.metricsHeight
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(TokyoNight.backgroundDeepColor.opacity(0.80))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.hideTabSwitcher()
                }

            VStack(spacing: 0) {
                searchHeader

                Rectangle()
                    .fill(TokyoNight.borderColor.opacity(0.72))
                    .frame(height: 1)

                tabList
            }
            .frame(maxWidth: 620)
            .background {
                ZStack {
                    ReaderSwitcherVisualEffectBackground()
                    TokyoNight.panelElevatedColor.opacity(0.86)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.95), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onAppear {
            selectedIndex = selectedIndexForCurrentTab()
        }
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
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor.opacity(0.95))
                .frame(width: 24, height: 24)

            ReaderSwitcherSearchField(
                text: $query,
                placeholder: language.text(.searchOpenTabs),
                onMoveUp: { moveSelection(.up) },
                onMoveDown: { moveSelection(.down) },
                onCommit: openSelectedMatch,
                onCancel: {
                    appState.hideTabSwitcher()
                }
            )
            .frame(height: 34)

            matchCount
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(TokyoNight.panelColor.opacity(0.92))
    }

    private var matchCount: some View {
        Text("\(matches.count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(matches.isEmpty ? TokyoNight.redColor : TokyoNight.cyanColor)
            .frame(minWidth: 34, minHeight: 24)
            .padding(.horizontal, 8)
            .background(TokyoNight.backgroundDeepColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        matches.isEmpty
                            ? TokyoNight.redColor.opacity(0.42)
                            : TokyoNight.cyanColor.opacity(0.28),
                        lineWidth: 1
                    )
            }
    }

    private var tabList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if matches.isEmpty {
                        emptyRow
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, tab in
                            TabSwitcherRow(
                                tab: tab,
                                isSelected: index == selectedIndex,
                                isCurrent: tab.id == appState.selectedTabID
                            )
                            .id(tab.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                open(tab)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: listHeight)
            .background(TokyoNight.panelElevatedColor.opacity(0.82))
            .onChange(of: selectedTabIDForScroll) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 22)

            Text(language.text(.noMatchingTabs))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TokyoNight.mutedColor)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var selectedTabIDForScroll: PDFTab.ID? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex].id
    }

    private func selectedIndexForCurrentTab() -> Int {
        guard let selectedTabID = appState.selectedTabID,
              let index = matches.firstIndex(where: { $0.id == selectedTabID }) else {
            return 0
        }
        return index
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
        open(matches[selectedIndex])
    }

    private func open(_ tab: PDFTab) {
        appState.selectTabFromSwitcher(tab.id)
    }
}

private struct TabSwitcherRow: View {
    @Environment(\.appUILanguage) private var language
    static let metricsHeight: CGFloat = 58
    let tab: PDFTab
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "doc.fill" : "doc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)
                    .lineLimit(1)

                Text(tab.url?.path ?? language.text(.untitled))
                    .font(.system(size: 11))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TokyoNight.cyanColor)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.metricsHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(TokyoNight.cyanColor)
                    .frame(width: 3)
            }
        }
    }

    private var iconColor: Color {
        if isSelected {
            return TokyoNight.cyanColor
        }
        return isCurrent ? TokyoNight.blueColor : TokyoNight.mutedColor
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(isSelected ? TokyoNight.selectionColor.opacity(0.82) : Color.clear)
    }
}

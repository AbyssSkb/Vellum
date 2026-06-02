import SwiftUI

struct TabSwitcherOverlay: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFocused: Bool
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.hideTabSwitcher()
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TokyoNight.mutedColor)

                    TextField("Search tabs", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TokyoNight.foregroundColor)
                        .focused($isSearchFocused)
                        .onSubmit {
                            openSelectedMatch()
                        }
                }
                .frame(height: 56)
                .padding(.horizontal, 18)
                .background(TokyoNight.panelElevatedColor)

                TokyoNightDivider(axis: .horizontal)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
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
                    .frame(maxHeight: 322)
                    .onChange(of: selectedTabIDForScroll) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: 560)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.95), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onAppear {
            selectedIndex = selectedIndexForCurrentTab()
            isSearchFocused = true
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
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand {
            appState.hideTabSwitcher()
        }
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
    let tab: PDFTab
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "doc.fill" : "doc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? TokyoNight.cyanColor : TokyoNight.blueColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)
                    .lineLimit(1)

                Text(tab.url?.path ?? "Untitled")
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
        .frame(height: 58)
        .background(isSelected ? TokyoNight.selectionColor.opacity(0.62) : Color.clear)
    }
}

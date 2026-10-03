@preconcurrency import AppKit
import SwiftUI

struct TabButton: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    let tab: PDFTab
    let isSelected: Bool
    let width: CGFloat
    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: width < 70 ? 4 : 7) {
            ClippedTabTitle(title: tab.title, isSelected: isSelected)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            if isSelected, width >= 90 {
                Button {
                    appState.closeSelectedTab()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(TokyoNight.foregroundColor.opacity(isCloseHovered ? 0.95 : 0.68))
                        .frame(width: 22, height: 22)
                        .background(isCloseHovered ? TokyoNight.selectionColor : .clear,
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(language.text(.closeTab))
                .accessibilityLabel(language.text(.closeTabNamed(tab.title)))
                .onHover { isCloseHovered = $0 }
            }
        }
        .padding(.leading, width < 70 ? 6 : 12)
        .padding(.trailing, isSelected && width >= 90 ? 8 : (width < 70 ? 6 : 12))
        .frame(width: width, height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture {
            if !isSelected {
                appState.selectTab(tab.id)
            }
        }
        .background(
            TabMiddleClickMonitor {
                appState.closeTab(tab.id)
            }
        )
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction {
            appState.selectTab(tab.id)
        }
        .background(
            isSelected
                ? TokyoNight.backgroundColor
                : TokyoNight.panelColor.opacity(isHovered ? 0.6 : 0)
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(TokyoNight.blueColor.opacity(0.8))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isCloseHovered)
    }
}

private struct TabMiddleClickMonitor: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> TabMiddleClickMonitorView {
        let view = TabMiddleClickMonitorView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ view: TabMiddleClickMonitorView, context: Context) {
        view.onMiddleClick = onMiddleClick
    }

    static func dismantleNSView(_ view: TabMiddleClickMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class TabMiddleClickMonitorView: NSView {
    var onMiddleClick: (() -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startMonitoring()
    }

    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2,
              let window,
              event.window === window else {
            return event
        }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }

        onMiddleClick?()
        return nil
    }
}

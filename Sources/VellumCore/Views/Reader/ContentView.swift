@preconcurrency import AppKit
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue

    public init() {}

    public var body: some View {
        let joinsLeadingTab = appState.hasOpenTabs && appState.isOutlineVisible
            && appState.tabs.first?.id == appState.selectedTabID
        let readerShape = UnevenRoundedRectangle(
            topLeadingRadius: joinsLeadingTab ? 0 : 8,
            bottomLeadingRadius: 8,
            bottomTrailingRadius: 8,
            topTrailingRadius: 8,
            style: .continuous
        )

        ZStack {
            VStack(spacing: 0) {
                if appState.hasOpenTabs {
                    TabStrip()
                }

                HStack(spacing: 0) {
                    if appState.isOutlineVisible, appState.hasOpenTabs {
                        OutlineSidebar(tab: appState.selectedTab)
                            .frame(width: 256)
                    }

                    ReaderStack()
                        .clipShape(readerShape)
                        .background {
                            readerShape
                                .fill(TokyoNight.panelColor)
                        }
                        .overlay {
                            readerShape
                                .strokeBorder(
                                    LinearGradient(colors: [TokyoNight.foregroundColor.opacity(0.10),
                                                            TokyoNight.foregroundColor.opacity(0.025)],
                                                   startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.5
                                )
                                .mask(Rectangle().padding(.top, appState.hasOpenTabs ? 1 : 0))
                                .allowsHitTesting(false)
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .padding(.leading, appState.isOutlineVisible && appState.hasOpenTabs ? 0 : 12)
                        .padding(.top, appState.hasOpenTabs ? 0 : 12)
                }
                .background(TokyoNight.backgroundDeepColor)
            }

            if appState.isTabSwitcherPresented {
                TabSwitcherOverlay()
            }

            if appState.isAIConversationHistoryPresented {
                AIConversationHistorySwitcherOverlay()
            }

            if appState.isAIExplanationHistoryPresented {
                AIExplanationHistorySwitcherOverlay()
            }
        }
        .overlay(alignment: .top) {
            TitlebarDragRegion(hasOpenTabs: appState.hasOpenTabs)
                .frame(height: 46)
        }
        .foregroundStyle(TokyoNight.foregroundColor)
        .tint(TokyoNight.blueColor)
        .background(TokyoNight.backgroundColor)
        .preferredColorScheme(.dark)
        .environment(\.appUILanguage, AppUILanguage.saved(rawValue: appLanguage))
        .background(WindowChromeConfigurator(appState: appState))
        .ignoresSafeArea(.container, edges: .top)
        .onOpenURL { url in
            guard url.isFileURL else { return }
            OpenURLRelay.shared.open([url])
        }
        .onAppear {
            appState.restorePreviousTabsIfNeeded()
        }
}
}

struct WindowChromeConfigurator: NSViewRepresentable {
    weak var appState: AppState?

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.appState = appState
        return view
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.appState = appState
        nsView.configureWindow()
    }

    class ChromeView: NSView {
        weak var appState: AppState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        override func layout() {
            super.layout()
            guard let window else { return }
            centerTrafficLights(in: window)
        }

        func configureWindow() {
            guard let window else { return }
            appState?.readerWindow = window

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.isMovableByWindowBackground = false
            window.isOpaque = false
            window.backgroundColor = .clear
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                self.centerTrafficLights(in: window)
            }
        }

        private func centerTrafficLights(in window: NSWindow) {
            let buttons = [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton)
            ].compactMap { $0 }
            guard let referenceButton = buttons.first else { return }
            let containerHeight = referenceButton.superview?.bounds.height ?? referenceButton.frame.maxY

            let targetCenterFromTop: CGFloat = 23
            let leftInset: CGFloat = 22
            let y = round(containerHeight - targetCenterFromTop - referenceButton.frame.height / 2)

            var x = leftInset
            for index in buttons.indices {
                if index > 0 {
                    let previous = buttons[index - 1]
                    let current = buttons[index]
                    x += max(18, current.frame.minX - previous.frame.minX)
                }
                buttons[index].setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }
}

@preconcurrency import AppKit
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let emptyLayout = EmptyReaderLayout(size: geometry.size)
            let joinsLeadingTab = appState.hasOpenTabs && appState.isOutlineVisible
                && appState.tabs.first?.id == appState.selectedTabID
            let edgeInset = emptyLayout.inset
            let cornerRadius = emptyLayout.cornerRadius
            let readerShape = UnevenRoundedRectangle(
                topLeadingRadius: joinsLeadingTab ? 0 : cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: cornerRadius,
                style: appState.hasOpenTabs ? .continuous : .circular
            )

            ZStack {
                VStack(spacing: 0) {
                    if appState.hasOpenTabs {
                        TabStrip(edgeInset: edgeInset)
                    }

                    HStack(spacing: 0) {
                        if appState.isOutlineVisible, appState.hasOpenTabs {
                            OutlineSidebar(tab: appState.selectedTab)
                                .frame(width: 256)
                                .padding(.leading, edgeInset)
                                .padding(.bottom, edgeInset)
                        }

                        ReaderStack(emptyScale: emptyLayout.scale)
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
                            .padding(.trailing, edgeInset)
                            .padding(.bottom, edgeInset)
                            .padding(.leading, appState.isOutlineVisible && appState.hasOpenTabs ? 0 : edgeInset)
                            .padding(.top, appState.hasOpenTabs ? 0 : edgeInset)
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
                    .frame(height: appState.hasOpenTabs ? 38 + edgeInset : 46)
            }
            .foregroundStyle(TokyoNight.foregroundColor)
            .tint(TokyoNight.blueColor)
            .background(TokyoNight.backgroundColor)
            .preferredColorScheme(.dark)
            .environment(\.appUILanguage, AppUILanguage.saved(rawValue: appLanguage))
            .background(WindowChromeConfigurator(appState: appState))
        }
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
        private var observedTrafficLightViews: [(view: NSView, postsChanges: Bool)] = []
        private var isTrafficLightLayoutScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObservingTrafficLightFrames()
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
            scheduleTrafficLightLayout()
        }

        @objc private func trafficLightFrameDidChange(_ notification: Notification) {
            scheduleTrafficLightLayout()
        }

        private func scheduleTrafficLightLayout() {
            // Native titlebar controls can reflow without the window being resized.
            guard !isTrafficLightLayoutScheduled else { return }
            isTrafficLightLayoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isTrafficLightLayoutScheduled = false
                guard let window = self.window else { return }
                self.centerTrafficLights(in: window)
            }
        }

        private func stopObservingTrafficLightFrames() {
            for (view, postsChanges) in observedTrafficLightViews {
                NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: view)
                view.postsFrameChangedNotifications = postsChanges
            }
            observedTrafficLightViews.removeAll()
        }

        private func centerTrafficLights(in window: NSWindow) {
            let buttons = [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton)
            ].compactMap { $0 }
            guard let referenceButton = buttons.first else { return }
            if let titlebar = referenceButton.superview, let container = titlebar.superview {
                let views = [titlebar, container] + buttons
                if !observedTrafficLightViews.map(\.view).elementsEqual(views, by: { $0 === $1 }) {
                    stopObservingTrafficLightFrames()
                    for view in views {
                        observedTrafficLightViews.append((view, view.postsFrameChangedNotifications))
                        view.postsFrameChangedNotifications = true
                        NotificationCenter.default.addObserver(
                            self, selector: #selector(trafficLightFrameDidChange),
                            name: NSView.frameDidChangeNotification, object: view
                        )
                    }
                }
            }
            let containerHeight = referenceButton.superview?.bounds.height ?? referenceButton.frame.maxY

            let targetCenterFromTop: CGFloat = 23
            let leftInset: CGFloat = 22
            let y = containerHeight - targetCenterFromTop - referenceButton.frame.height / 2

            for index in buttons.indices {
                let origin = NSPoint(x: leftInset + CGFloat(index) * 20, y: y)
                if buttons[index].frame.origin != origin {
                    buttons[index].setFrameOrigin(origin)
                }
            }
        }
    }
}

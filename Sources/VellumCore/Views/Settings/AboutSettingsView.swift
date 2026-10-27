@preconcurrency import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.appUILanguage) private var language
    @AppStorage(AppPreferenceKeys.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates = true
    private let releaseNotes = AppBundledReleaseNotes.sections()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                updatesSection
                releaseNotesSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VellumColors.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Vellum")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(VellumColors.foregroundColor)

                Text(appVersionText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(VellumColors.mutedColor)
            }

            Spacer()
        }
        .padding(.bottom, 2)
    }

    private var updatesSection: some View {
        GeneralSettingsPanel(title: language.text(.updates), systemImage: "arrow.triangle.2.circlepath") {
            VStack(spacing: 0) {
                GeneralToggleRow(
                    id: "automatic-updates",
                    title: language.text(.automaticallyCheck),
                    subtitle: language.text(.automaticallyCheckSubtitle),
                    isOn: $automaticallyCheckForUpdates
                )

                HStack {
                    Button(action: checkForUpdates) {
                        Label(language.text(.checkNow), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GeneralActionButtonStyle())
                    .settingsControl("check-now", action: checkForUpdates)

                    Spacer()
                }
                .padding(.vertical, 12)
                .frame(minHeight: 54)
                .settingsRow("check-updates")
            }
        }
    }

    private var releaseNotesSection: some View {
        GeneralSettingsPanel(title: language.text(.currentReleaseNotes), systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 12) {
                if releaseNotes.isEmpty {
                    Text(language.text(.localReleaseNotesUnavailable))
                        .font(.system(size: 12.5))
                        .foregroundStyle(VellumColors.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(releaseNotes.enumerated()), id: \.offset) { _, section in
                        ForEach(Array(section.notes.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("•")
                                    .foregroundStyle(VellumColors.mutedColor)
                                Text(note)
                                    .foregroundStyle(VellumColors.foregroundColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsReadingArea("release-notes")
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.nilIfEmpty ?? language.text(.developmentBuild)
    }

    private func checkForUpdates() {
        NotificationCenter.default.post(name: VellumAppNotification.checkForUpdatesRequested, object: nil)
    }
}

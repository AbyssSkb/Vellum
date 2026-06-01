@preconcurrency import AppKit
import Foundation
import VellumCore

@MainActor
final class GitHubUpdateChecker {
    enum CheckMode {
        case automatic
        case manual
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/releases/latest")!
    private static let defaultDownloadURL = URL(string: "https://github.com/AbyssSkb/Vellum/releases/latest")!
    private static let lastPromptedVersionKey = "VellumLastPromptedUpdateVersion"

    private let session: URLSession
    private var task: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        task?.cancel()
    }

    func checkForUpdates(_ mode: CheckMode) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let update = try await fetchLatestUpdate()
                await MainActor.run {
                    self.handle(update: update, mode: mode)
                }
            } catch {
                await MainActor.run {
                    if mode == .manual {
                        self.showUpdateError(error)
                    }
                }
            }
        }
    }

    func checkAutomaticallySoon() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            do {
                let update = try await fetchLatestUpdate()
                await MainActor.run {
                    self.handle(update: update, mode: .automatic)
                }
            } catch {
                // Background checks stay quiet. The menu action reports errors.
            }
        }
    }

    private func fetchLatestUpdate() async throws -> AppUpdateInfo {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(LatestRelease.self, from: data)
        guard !release.draft, !release.prerelease else {
            throw URLError(.cannotParseResponse)
        }

        return AppUpdateInfo(version: release.tagName, releaseURL: release.htmlURL)
    }

    private func handle(update: AppUpdateInfo, mode: CheckMode) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard update.isNewer(than: currentVersion) else {
            if mode == .manual {
                showNoUpdate(currentVersion: currentVersion)
            }
            return
        }

        if mode == .automatic,
           UserDefaults.standard.string(forKey: Self.lastPromptedVersionKey) == update.version {
            return
        }

        UserDefaults.standard.set(update.version, forKey: Self.lastPromptedVersionKey)
        showUpdateAvailable(update: update, currentVersion: currentVersion)
    }

    private func showUpdateAvailable(update: AppUpdateInfo, currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Vellum \(update.version) is available"
        alert.informativeText = "You are currently using Vellum \(currentVersion). Open the releases page to download the latest version."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.releaseURL)
        }
    }

    private func showNoUpdate(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Vellum is up to date"
        alert.informativeText = "You are using Vellum \(currentVersion)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to check for updates"
        alert.informativeText = "Open the releases page to check manually."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.defaultDownloadURL)
        }
    }
}

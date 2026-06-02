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
        let assets: [ReleaseAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    private struct ReleaseAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct RepositoryTag: Decodable {
        let name: String
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/releases/latest")!
    private static let tagsAPIURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/tags")!
    private static let tagsPageURL = URL(string: "https://github.com/AbyssSkb/Vellum/tags")!
    private static let repositoryURL = URL(string: "https://github.com/AbyssSkb/Vellum")!
    private static let defaultDownloadURL = repositoryURL.appendingPathComponent("releases").appendingPathComponent("latest")
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
        do {
            return try await fetchLatestReleaseUpdate()
        } catch {
            do {
                return try await fetchLatestReleaseRedirectUpdate()
            } catch {
                return try await fetchLatestTaggedUpdate()
            }
        }
    }

    private func fetchLatestReleaseUpdate() async throws -> AppUpdateInfo {
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

        let installerAsset = AppUpdateCatalog.preferredInstallerAsset(
            in: release.assets.map {
                AppReleaseAsset(name: $0.name, downloadURL: $0.browserDownloadURL)
            }
        )

        return AppUpdateInfo(
            version: release.tagName,
            releaseURL: release.htmlURL,
            downloadURL: installerAsset?.downloadURL
        )
    }

    private func fetchLatestReleaseRedirectUpdate() async throws -> AppUpdateInfo {
        var request = URLRequest(url: Self.defaultDownloadURL)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url else {
            throw URLError(.badServerResponse)
        }

        let tagName = finalURL.lastPathComponent
        guard !tagName.isEmpty,
              tagName != "latest",
              tagName.hasPrefix("v") || tagName.hasPrefix("V") else {
            throw URLError(.cannotParseResponse)
        }

        return AppUpdateCatalog.githubReleaseUpdate(tagName: tagName, repositoryURL: Self.repositoryURL)
    }

    private func fetchLatestTaggedUpdate() async throws -> AppUpdateInfo {
        var request = URLRequest(url: Self.tagsAPIURL)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let tags = try JSONDecoder().decode([RepositoryTag].self, from: data)
        guard let update = AppUpdateCatalog.latestTaggedVersion(
            in: tags.map(\.name),
            tagsURL: Self.tagsPageURL
        ) else {
            throw URLError(.cannotParseResponse)
        }

        return update
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
        if update.downloadURL != nil {
            alert.informativeText = "You are currently using Vellum \(currentVersion). Download the latest installer now."
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Open GitHub")
            alert.addButton(withTitle: "Later")
        } else {
            alert.informativeText = "You are currently using Vellum \(currentVersion). Open GitHub to download the latest version."
            alert.addButton(withTitle: "Open GitHub")
            alert.addButton(withTitle: "Later")
        }

        let response = alert.runModal()
        if update.downloadURL != nil {
            if response == .alertFirstButtonReturn {
                downloadAndOpenInstaller(for: update)
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(update.releaseURL)
            }
        } else if response == .alertFirstButtonReturn {
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
        let alert = NSAlert()
        alert.messageText = "Unable to check for updates"
        alert.informativeText = "GitHub may be unreachable or rate-limited right now. You can open the releases page and try again later."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.defaultDownloadURL)
        }
    }

    private func downloadAndOpenInstaller(for update: AppUpdateInfo) {
        guard let downloadURL = update.downloadURL else {
            NSWorkspace.shared.open(update.releaseURL)
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL = try await downloadInstaller(from: downloadURL, version: update.version)
                await MainActor.run {
                    _ = NSWorkspace.shared.open(fileURL)
                }
            } catch {
                await MainActor.run {
                    self.showDownloadError(error, releaseURL: update.releaseURL)
                }
            }
        }
    }

    private func downloadInstaller(from url: URL, version: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileName = installerFileName(from: url, version: version)
        let destinationURL = downloadsDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func installerFileName(from url: URL, version: String) -> String {
        let lastPathComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return "Vellum-\(version)-macOS.dmg"
    }

    private func showDownloadError(_ error: Error, releaseURL: URL) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to download the update"
        alert.informativeText = "Open the release page to download it manually."
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }
}

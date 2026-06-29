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
        let body: String?
        let assets: [ReleaseAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case body
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
    private var downloadWindow: UpdateDownloadWindowController?

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
        let request = URLRequest(url: Self.latestReleaseURL)
        return try await fetchReleaseUpdate(request: request)
    }

    private func fetchReleaseUpdate(tagName: String) async throws -> AppUpdateInfo {
        guard let releaseURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/releases/tags/\(tagName)") else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: releaseURL)
        return try await fetchReleaseUpdate(request: request)
    }

    private func fetchReleaseUpdate(request: URLRequest) async throws -> AppUpdateInfo {
        var request = request
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
            downloadURL: installerAsset?.downloadURL,
            releaseNotes: normalizedReleaseNotes(release.body)
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

        do {
            return try await fetchReleaseUpdate(tagName: tagName)
        } catch {
            return AppUpdateCatalog.githubReleaseUpdate(tagName: tagName, repositoryURL: Self.repositoryURL)
        }
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

        do {
            return try await fetchReleaseUpdate(tagName: update.version)
        } catch {
            return update
        }
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

        showUpdateAvailable(update: update, currentVersion: currentVersion, mode: mode)
    }

    private func showUpdateAvailable(update: AppUpdateInfo, currentVersion: String, mode: CheckMode) {
        let alert = NSAlert()
        alert.messageText = "Vellum \(update.version) is available"
        let releaseNotesSummary = releaseNotesSummary(update.releaseNotes)
        if update.downloadURL != nil {
            alert.informativeText = "You are currently using Vellum \(currentVersion). Download and install the latest version now.\(releaseNotesSummary)"
            alert.addButton(withTitle: "Download and Install")
            alert.addButton(withTitle: "Open GitHub")
            alert.addButton(withTitle: "Later")
        } else {
            alert.informativeText = "You are currently using Vellum \(currentVersion). Open GitHub to download the latest version.\(releaseNotesSummary)"
            alert.addButton(withTitle: "Open GitHub")
            alert.addButton(withTitle: "Later")
        }

        let response = alert.runModal()
        if update.downloadURL != nil {
            if response == .alertFirstButtonReturn {
                downloadAndOpenInstaller(for: update, mode: mode)
            } else if response == .alertSecondButtonReturn {
                markPromptedIfNeeded(update: update, mode: mode)
                NSWorkspace.shared.open(update.releaseURL)
            } else if response == .alertThirdButtonReturn {
                markPromptedIfNeeded(update: update, mode: mode)
            }
        } else if response == .alertFirstButtonReturn {
            markPromptedIfNeeded(update: update, mode: mode)
            NSWorkspace.shared.open(update.releaseURL)
        } else if response == .alertSecondButtonReturn {
            markPromptedIfNeeded(update: update, mode: mode)
        }
    }

    private func markPromptedIfNeeded(update: AppUpdateInfo, mode: CheckMode) {
        guard mode == .automatic else { return }
        UserDefaults.standard.set(update.version, forKey: Self.lastPromptedVersionKey)
    }

    private func showNoUpdate(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Vellum is up to date"
        alert.informativeText = "You are using Vellum \(currentVersion)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func normalizedReleaseNotes(_ rawNotes: String?) -> String? {
        let notes = rawNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else { return nil }
        return notes
    }

    private func releaseNotesSummary(_ releaseNotes: String?) -> String {
        guard let releaseNotes else { return "" }
        let lines = releaseNotes
            .split(whereSeparator: \.isNewline)
            .compactMap(cleanReleaseNoteLine)

        guard !lines.isEmpty else { return "" }
        return "\n\nWhat's new:\n" + lines.prefix(4).joined(separator: "\n")
    }

    private func cleanReleaseNoteLine(_ rawLine: Substring) -> String? {
        var line = String(rawLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        line = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowercasedLine = line.lowercased()
        guard !lowercasedLine.hasPrefix("what's changed"),
              !lowercasedLine.hasPrefix("full changelog") else {
            return nil
        }

        if line.hasPrefix("-") {
            line = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !line.isEmpty else { return nil }
        return "- \(line)"
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

    private func downloadAndOpenInstaller(for update: AppUpdateInfo, mode: CheckMode) {
        guard let downloadURL = update.downloadURL else {
            NSWorkspace.shared.open(update.releaseURL)
            return
        }

        task?.cancel()
        let window = UpdateDownloadWindowController(version: update.version)
        downloadWindow = window
        window.onCancel = { [weak self] in
            self?.task?.cancel()
            self?.downloadWindow?.finish()
            self?.downloadWindow = nil
        }
        window.show()

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL = try await downloadInstaller(
                    from: downloadURL,
                    version: update.version
                ) { [weak window] receivedBytes, totalBytes in
                    window?.updateProgress(receivedBytes: receivedBytes, totalBytes: totalBytes)
                }
                await MainActor.run {
                    window.updateStatus(
                        "Installing Vellum \(update.version)",
                        detail: "Vellum will quit, update itself, and reopen.",
                        indeterminate: true,
                        canCancel: false
                    )
                    self.markPromptedIfNeeded(update: update, mode: mode)
                    do {
                        try AppUpdateInstaller.installAndRelaunch(from: fileURL)
                    } catch {
                        window.finish()
                        self.downloadWindow = nil
                        self.showInstallError(error, diskImageURL: fileURL)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    window.finish()
                    self.downloadWindow = nil
                }
            } catch {
                await MainActor.run {
                    window.finish()
                    self.downloadWindow = nil
                    self.showDownloadError(error, releaseURL: update.releaseURL)
                }
            }
        }
    }

    private func downloadInstaller(
        from url: URL,
        version: String,
        progress: @MainActor @escaping (Int64, Int64?) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileName = installerFileName(from: url, version: version)
        let destinationURL = downloadsDirectory.appendingPathComponent(fileName)
        let temporaryDownloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vellum-\(UUID().uuidString).download")

        FileManager.default.createFile(atPath: temporaryDownloadURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: temporaryDownloadURL)
        var shouldRemoveTemporaryDownload = true
        defer {
            if shouldRemoveTemporaryDownload {
                try? FileManager.default.removeItem(at: temporaryDownloadURL)
            }
        }

        defer {
            try? fileHandle.close()
        }

        let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        var receivedBytes: Int64 = 0
        let progressReportByteInterval: Int64 = 32 * 1024
        let progressReportTimeInterval: TimeInterval = 0.05
        var lastReportedBytes: Int64 = 0
        var lastProgressReportDate = Date()
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        await MainActor.run {
            progress(receivedBytes, totalBytes)
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            receivedBytes += 1

            if buffer.count >= 64 * 1024 {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            let now = Date()
            if receivedBytes - lastReportedBytes >= progressReportByteInterval
                || now.timeIntervalSince(lastProgressReportDate) >= progressReportTimeInterval {
                lastReportedBytes = receivedBytes
                lastProgressReportDate = now
                await MainActor.run {
                    progress(receivedBytes, totalBytes)
                }
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }
        try fileHandle.close()

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryDownloadURL, to: destinationURL)
        shouldRemoveTemporaryDownload = false

        await MainActor.run {
            progress(receivedBytes, totalBytes)
        }
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
        let alert = NSAlert()
        alert.messageText = "Unable to download the update"
        alert.informativeText = "\(error.localizedDescription)\n\nOpen the release page to download it manually."
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func showInstallError(_ error: Error, diskImageURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Unable to install the update"
        alert.informativeText = "\(error.localizedDescription)\n\nThe installer was downloaded. Open the disk image and install it manually."
        alert.addButton(withTitle: "Open Disk Image")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(diskImageURL)
        }
    }
}

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
    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/releases?per_page=100")!
    private static let releasesAtomURL = URL(string: "https://github.com/AbyssSkb/Vellum/releases.atom")!
    private static let tagsAPIURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/tags")!
    private static let tagsPageURL = URL(string: "https://github.com/AbyssSkb/Vellum/tags")!
    private static let repositoryURL = URL(string: "https://github.com/AbyssSkb/Vellum")!
    private static let defaultDownloadURL = repositoryURL.appendingPathComponent("releases").appendingPathComponent("latest")
    private static let lastPromptedVersionKey = "VellumLastPromptedUpdateVersion"
    private static let releaseNotesRetryDelay: UInt64 = 600_000_000

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
                let currentVersion = self.currentAppVersion()
                let update = try await fetchLatestUpdate(currentVersion: currentVersion)
                await MainActor.run {
                    self.handle(update: update, currentVersion: currentVersion, mode: mode)
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
                let currentVersion = self.currentAppVersion()
                let update = try await fetchLatestUpdate(currentVersion: currentVersion)
                await MainActor.run {
                    self.handle(update: update, currentVersion: currentVersion, mode: .automatic)
                }
            } catch {
                // Background checks stay quiet. The menu action reports errors.
            }
        }
    }

    private func fetchLatestUpdate(currentVersion: String) async throws -> AppUpdateInfo {
        var latestReleaseUpdate: AppUpdateInfo?
        var latestReleaseError: Error?

        do {
            latestReleaseUpdate = try await fetchLatestReleaseUpdate()
        } catch {
            latestReleaseError = error
        }

        do {
            let redirectUpdate = try await fetchLatestReleaseRedirectUpdate()
            if let latestReleaseUpdate,
               !redirectUpdate.isNewer(than: latestReleaseUpdate.version) {
                return await updateIncludingReleaseHistory(latestReleaseUpdate, currentVersion: currentVersion)
            }
            return await updateIncludingReleaseHistory(redirectUpdate, currentVersion: currentVersion)
        } catch {
            if let latestReleaseUpdate {
                return await updateIncludingReleaseHistory(latestReleaseUpdate, currentVersion: currentVersion)
            }

            do {
                let update = try await fetchLatestTaggedUpdate()
                return await updateIncludingReleaseHistory(update, currentVersion: currentVersion)
            } catch {
                throw latestReleaseError ?? error
            }
        }
    }

    private func fetchLatestReleaseUpdate() async throws -> AppUpdateInfo {
        let request = githubAPIRequest(url: Self.latestReleaseURL)
        return try await fetchReleaseUpdate(request: request)
    }

    private func fetchReleaseUpdate(tagName: String) async throws -> AppUpdateInfo {
        guard let releaseURL = URL(string: "https://api.github.com/repos/AbyssSkb/Vellum/releases/tags/\(tagName)") else {
            throw URLError(.badURL)
        }

        let request = githubAPIRequest(url: releaseURL)
        return try await fetchReleaseUpdate(request: request)
    }

    private func fetchReleaseUpdate(request: URLRequest, retriesEmptyNotes: Bool = true) async throws -> AppUpdateInfo {
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

        var releaseNotes = normalizedReleaseNotes(release.body)
        if releaseNotes == nil, retriesEmptyNotes {
            try await Task.sleep(nanoseconds: Self.releaseNotesRetryDelay)
            return try await fetchReleaseUpdate(request: request, retriesEmptyNotes: false)
        }
        if releaseNotes == nil {
            releaseNotes = try? await fetchReleaseNotesFromAtom(tagName: release.tagName)
        }

        return AppUpdateInfo(
            version: release.tagName,
            releaseURL: release.htmlURL,
            downloadURL: installerAsset?.downloadURL,
            releaseNotes: releaseNotes
        )
    }

    private func fetchLatestReleaseRedirectUpdate() async throws -> AppUpdateInfo {
        let request = githubWebRequest(url: Self.defaultDownloadURL)

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
            return try await fallbackGitHubReleaseUpdate(tagName: tagName)
        }
    }

    private func fetchLatestTaggedUpdate() async throws -> AppUpdateInfo {
        let request = githubAPIRequest(url: Self.tagsAPIURL)

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
            return AppUpdateInfo(
                version: update.version,
                releaseURL: update.releaseURL,
                downloadURL: update.downloadURL,
                releaseNotes: try? await fetchReleaseNotesFromAtom(tagName: update.version)
            )
        }
    }

    private func fallbackGitHubReleaseUpdate(tagName: String) async throws -> AppUpdateInfo {
        let update = AppUpdateCatalog.githubReleaseUpdate(tagName: tagName, repositoryURL: Self.repositoryURL)
        return AppUpdateInfo(
            version: update.version,
            releaseURL: update.releaseURL,
            downloadURL: update.downloadURL,
            releaseNotes: try? await fetchReleaseNotesFromAtom(tagName: tagName)
        )
    }

    private func updateIncludingReleaseHistory(_ update: AppUpdateInfo, currentVersion: String) async -> AppUpdateInfo {
        guard update.isNewer(than: currentVersion),
              let releaseNotes = try? await fetchReleaseHistoryNotes(currentVersion: currentVersion, latestVersion: update.version) else {
            return update
        }

        return AppUpdateInfo(
            version: update.version,
            releaseURL: update.releaseURL,
            downloadURL: update.downloadURL,
            releaseNotes: releaseNotes
        )
    }

    private func fetchReleaseHistoryNotes(currentVersion: String, latestVersion: String) async throws -> String? {
        let request = githubAPIRequest(url: Self.releasesAPIURL)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let current = UpdateVersion(currentVersion)
        let latest = UpdateVersion(latestVersion)
        let releases = try JSONDecoder().decode([LatestRelease].self, from: data)
            .filter { release in
                guard !release.draft, !release.prerelease else { return false }
                let version = UpdateVersion(release.tagName)
                return version > current && version <= latest
            }
            .sorted { UpdateVersion($0.tagName) > UpdateVersion($1.tagName) }

        let sections = await releaseHistorySections(from: Array(releases.prefix(12)))
        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private func releaseHistorySections(from releases: [LatestRelease]) async -> [String] {
        var sections: [String] = []

        for release in releases {
            var releaseNotes = normalizedReleaseNotes(release.body)
            if releaseNotes == nil {
                releaseNotes = try? await fetchReleaseNotesFromAtom(tagName: release.tagName)
            }

            guard let releaseNotes else { continue }
            sections.append("## \(release.tagName)\n\(releaseNotes)")
        }

        return sections
    }

    private func fetchReleaseNotesFromAtom(tagName: String) async throws -> String? {
        let request = githubAtomRequest(url: Self.releasesAtomURL)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return ReleaseNotesAtomParser.releaseNotes(for: tagName, from: data)
    }

    private func handle(update: AppUpdateInfo, currentVersion: String, mode: CheckMode) {
        guard update.isNewer(than: currentVersion) else {
            if mode == .manual {
                showNoUpdate(currentVersion: currentVersion, latestVersion: update.version)
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
        let alert = UpdateAvailableWindowController(
            updateVersion: update.version,
            currentVersion: currentVersion,
            canInstall: update.downloadURL != nil,
            releaseNotes: AppReleaseNotesParser.sections(from: update.releaseNotes)
        )

        switch alert.runModal() {
        case .install:
            downloadAndOpenInstaller(for: update, mode: mode)
        case .openGitHub:
            markPromptedIfNeeded(update: update, mode: mode)
            NSWorkspace.shared.open(update.releaseURL)
        case .later:
            markPromptedIfNeeded(update: update, mode: mode)
        }
    }

    private func markPromptedIfNeeded(update: AppUpdateInfo, mode: CheckMode) {
        guard mode == .automatic else { return }
        UserDefaults.standard.set(update.version, forKey: Self.lastPromptedVersionKey)
    }

    private func showNoUpdate(currentVersion: String, latestVersion: String) {
        let language = AppUILanguage.saved()
        let alert = NSAlert()
        alert.messageText = language.text(.upToDate)
        alert.informativeText = language.text(.upToDateDetail(current: currentVersion, latest: latestVersion))
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func normalizedReleaseNotes(_ rawNotes: String?) -> String? {
        let notes = rawNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else { return nil }
        return notes
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func githubAPIRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private func githubWebRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("Vellum", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private func githubAtomRequest(url: URL) -> URLRequest {
        var request = githubWebRequest(url: url)
        request.setValue("application/atom+xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    private func showUpdateError(_ error: Error) {
        let language = AppUILanguage.saved()
        let alert = NSAlert()
        alert.messageText = language.text(.unableToCheckUpdates)
        alert.informativeText = language.text(.unableToCheckUpdatesDetail)
        alert.addButton(withTitle: language.text(.openReleases))
        alert.addButton(withTitle: language.text(.cancel))

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
                        AppUILanguage.saved().text(.installingVersion(update.version)),
                        detail: AppUILanguage.saved().text(.installingDetail),
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
        let language = AppUILanguage.saved()
        let alert = NSAlert()
        alert.messageText = language.text(.unableToDownloadUpdate)
        alert.informativeText = language.text(.unableToDownloadUpdateDetail(error.localizedDescription))
        alert.addButton(withTitle: language.text(.openGitHub))
        alert.addButton(withTitle: language.text(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func showInstallError(_ error: Error, diskImageURL: URL) {
        let language = AppUILanguage.saved()
        let alert = NSAlert()
        alert.messageText = language.text(.unableToInstallUpdate)
        alert.informativeText = language.text(.unableToInstallUpdateDetail(error.localizedDescription))
        alert.addButton(withTitle: language.text(.openDiskImage))
        alert.addButton(withTitle: language.text(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(diskImageURL)
        }
    }
}

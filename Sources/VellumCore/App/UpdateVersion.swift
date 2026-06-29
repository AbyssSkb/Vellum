import Foundation

public struct UpdateVersion: Comparable, Equatable {
    public let components: [Int]

    public init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed

        self.components = normalized
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }

    public static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

public struct AppUpdateInfo: Equatable {
    public let version: String
    public let releaseURL: URL
    public let downloadURL: URL?
    public let releaseNotes: String?

    public init(version: String, releaseURL: URL, downloadURL: URL? = nil, releaseNotes: String? = nil) {
        self.version = version
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
    }

    public func isNewer(than currentVersion: String) -> Bool {
        UpdateVersion(version) > UpdateVersion(currentVersion)
    }
}

public struct AppReleaseAsset: Equatable {
    public let name: String
    public let downloadURL: URL

    public init(name: String, downloadURL: URL) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

public enum AppUpdateCatalog {
    public static func githubReleaseUpdate(tagName: String, repositoryURL: URL) -> AppUpdateInfo {
        let version = tagName.hasPrefix("v") || tagName.hasPrefix("V")
            ? String(tagName.dropFirst())
            : tagName
        let releaseURL = repositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("tag")
            .appendingPathComponent(tagName)
        let downloadURL = repositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("download")
            .appendingPathComponent(tagName)
            .appendingPathComponent("Vellum-\(version)-macOS.dmg")

        return AppUpdateInfo(
            version: tagName,
            releaseURL: releaseURL,
            downloadURL: downloadURL
        )
    }

    public static func latestTaggedVersion(
        in tagNames: [String],
        tagsURL: URL
    ) -> AppUpdateInfo? {
        tagNames
            .filter { !$0.isEmpty && ($0.hasPrefix("v") || $0.hasPrefix("V")) }
            .max { UpdateVersion($0) < UpdateVersion($1) }
            .map { AppUpdateInfo(version: $0, releaseURL: tagsURL) }
    }

    public static func preferredInstallerAsset(in assets: [AppReleaseAsset]) -> AppReleaseAsset? {
        let diskImages = assets.filter { asset in
            let lowercasedName = asset.name.lowercased()
            return lowercasedName.hasSuffix(".dmg")
        }

        return diskImages.first { asset in
            let lowercasedName = asset.name.lowercased()
            return lowercasedName.contains("vellum") && lowercasedName.contains("macos")
        } ?? diskImages.first { asset in
            asset.name.lowercased().contains("vellum")
        } ?? diskImages.first
    }
}

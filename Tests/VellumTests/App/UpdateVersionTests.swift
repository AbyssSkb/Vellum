import Foundation
import Testing
@testable import VellumCore

@Suite("Update version")
struct UpdateVersionTests {
    @Test
    func versionComparisonIgnoresVPrefixAndPadsComponents() {
        #expect(UpdateVersion("v0.2.2") == UpdateVersion("0.2.2"))
        #expect(UpdateVersion("0.2.10") > UpdateVersion("0.2.2"))
        #expect(UpdateVersion("0.3") > UpdateVersion("0.2.99"))
        #expect(UpdateVersion("1.0") == UpdateVersion("1.0.0"))
    }

    @Test
    func updateInfoDetectsNewerReleaseTags() {
        let update = AppUpdateInfo(
            version: "v0.2.3",
            releaseURL: URL(string: "https://github.com/AbyssSkb/Vellum/releases/tag/v0.2.3")!,
            releaseNotes: "- Fixed search"
        )

        #expect(update.isNewer(than: "0.2.2"))
        #expect(!update.isNewer(than: "0.2.3"))
        #expect(update.releaseNotes == "- Fixed search")
    }

    @Test
    func updateCatalogChoosesLatestVersionTag() {
        let tagsURL = URL(string: "https://github.com/AbyssSkb/Vellum/tags")!
        let update = AppUpdateCatalog.latestTaggedVersion(
            in: ["preview", "v0.2.8", "v0.2.10", "v0.1.0"],
            tagsURL: tagsURL
        )

        #expect(update == AppUpdateInfo(version: "v0.2.10", releaseURL: tagsURL))
        #expect(update?.releaseNotes == nil)
    }

    @Test
    func updateCatalogBuildsGitHubReleaseDownloadURL() {
        let repositoryURL = URL(string: "https://github.com/AbyssSkb/Vellum")!
        let update = AppUpdateCatalog.githubReleaseUpdate(tagName: "v0.2.6", repositoryURL: repositoryURL)

        #expect(update.version == "v0.2.6")
        #expect(update.releaseURL == URL(string: "https://github.com/AbyssSkb/Vellum/releases/tag/v0.2.6"))
        #expect(update.downloadURL == URL(string: "https://github.com/AbyssSkb/Vellum/releases/download/v0.2.6/Vellum-0.2.6-macOS.dmg"))
    }

    @Test
    func updateCatalogPrefersMacOSDiskImageAsset() {
        let genericDMG = AppReleaseAsset(
            name: "Other.dmg",
            downloadURL: URL(string: "https://example.com/other.dmg")!
        )
        let checksum = AppReleaseAsset(
            name: "Vellum-0.2.6-macOS.dmg.sha256",
            downloadURL: URL(string: "https://example.com/vellum.dmg.sha256")!
        )
        let macOSDMG = AppReleaseAsset(
            name: "Vellum-0.2.6-macOS.dmg",
            downloadURL: URL(string: "https://example.com/vellum.dmg")!
        )

        #expect(AppUpdateCatalog.preferredInstallerAsset(in: [genericDMG, checksum, macOSDMG]) == macOSDMG)
    }

    @Test
    func releaseNotesParserGroupsMultipleVersionSections() {
        let notes = """
        ## v0.6.29
        - Add AI request logs.
        - Add log controls.

        ## v0.6.28
        - Improve multi-selection prompts.

        Full Changelog: https://example.com
        """

        let sections = AppReleaseNotesParser.sections(from: notes)

        #expect(sections == [
            AppReleaseNotesSection(
                version: "v0.6.29",
                notes: ["Add AI request logs.", "Add log controls."]
            ),
            AppReleaseNotesSection(
                version: "v0.6.28",
                notes: ["Improve multi-selection prompts."]
            )
        ])
    }

    @Test
    func releaseNotesParserKeepsPlainLatestNotesCompact() {
        let notes = """
        What's Changed
        - Fixed update dialog.
        * Render release notes.
        """

        let sections = AppReleaseNotesParser.sections(from: notes)

        #expect(sections == [
            AppReleaseNotesSection(
                version: nil,
                notes: ["Fixed update dialog.", "Render release notes."]
            )
        ])
    }
}

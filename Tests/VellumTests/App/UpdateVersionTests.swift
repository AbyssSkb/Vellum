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
            releaseURL: URL(string: "https://github.com/AbyssSkb/Vellum/releases/tag/v0.2.3")!
        )

        #expect(update.isNewer(than: "0.2.2"))
        #expect(!update.isNewer(than: "0.2.3"))
    }

    @Test
    func updateCatalogChoosesLatestVersionTag() {
        let tagsURL = URL(string: "https://github.com/AbyssSkb/Vellum/tags")!
        let update = AppUpdateCatalog.latestTaggedVersion(
            in: ["preview", "v0.2.8", "v0.2.10", "v0.1.0"],
            tagsURL: tagsURL
        )

        #expect(update == AppUpdateInfo(version: "v0.2.10", releaseURL: tagsURL))
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
}

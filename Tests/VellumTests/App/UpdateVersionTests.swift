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
}

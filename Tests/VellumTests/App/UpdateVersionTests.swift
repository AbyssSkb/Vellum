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
    func releaseNotesParserGroupsMultipleVersionSections() {
        let notes = """
        ## v0.6.29
        - Add AI request logs.
        - Add log controls.
        **Full Changelog**: https://example.com/v0.6.28...v0.6.29

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
    func releaseNotesParserDropsChangelogLinksAfterMarkdownCleanup() {
        let notes = """
        What's Changed
        - Fix update notes styling.
        - **Full Changelog**: https://example.com/v0.6.42...v0.6.43
        * Full Changelog: https://example.com/v0.6.41...v0.6.42
        """

        let sections = AppReleaseNotesParser.sections(from: notes)

        #expect(sections == [
            AppReleaseNotesSection(
                version: nil,
                notes: ["Fix update notes styling."]
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

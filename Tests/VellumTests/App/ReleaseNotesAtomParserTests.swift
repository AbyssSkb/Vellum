import Foundation
import Testing
@testable import VellumCore

@Suite("Release notes Atom parser")
struct ReleaseNotesAtomParserTests {
    @Test
    func extractsReleaseNotesForMatchingTag() throws {
        let data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/v0.5.1</id>
            <title>Vellum 0.5.1</title>
            <content type="html">&lt;h2&gt;What&#39;s Changed&lt;/h2&gt;
        &lt;ul&gt;
        &lt;li&gt;Localize default AI prompt headings (&lt;a href=&quot;https://example.com&quot;&gt;&lt;tt&gt;80f624c&lt;/tt&gt;&lt;/a&gt;)&lt;/li&gt;
        &lt;/ul&gt;
        &lt;p&gt;&lt;strong&gt;Full Changelog&lt;/strong&gt;: &lt;a href=&quot;https://example.com&quot;&gt;&lt;tt&gt;v0.5.0...v0.5.1&lt;/tt&gt;&lt;/a&gt;&lt;/p&gt;</content>
          </entry>
        </feed>
        """.utf8)

        let notes = try #require(ReleaseNotesAtomParser.releaseNotes(for: "v0.5.1", from: data))

        #expect(notes.contains("## What's Changed"))
        #expect(notes.contains("- Localize default AI prompt headings (80f624c)"))
        #expect(notes.contains("Full Changelog: v0.5.0...v0.5.1"))
    }

    @Test
    func ignoresOtherTags() {
        let data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/v0.5.0</id>
            <content type="html">&lt;ul&gt;&lt;li&gt;Older release&lt;/li&gt;&lt;/ul&gt;</content>
          </entry>
        </feed>
        """.utf8)

        #expect(ReleaseNotesAtomParser.releaseNotes(for: "v0.5.1", from: data) == nil)
    }
}

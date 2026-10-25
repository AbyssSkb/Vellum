import Foundation
import Testing
import zlib
@testable import VellumCore

@Suite("Local MDict archives")
struct MDictArchiveTests {
    @Test(arguments: [false, true])
    func readsRecordsAcrossBlockBoundaries(compressed: Bool) async throws {
        let html = "<h1>hello</h1><p>你好 — a greeting</p>"
        let archive = try MDictFixture(entries: [("hello", Data(html.utf8)), ("world", Data("<p>world</p>".utf8))], compressed: compressed, splitAt: 17)
        let files = try DictionaryFiles(archive: archive.data)
        defer { files.cleanup() }

        let store = DictionaryStore()
        let entry = try await store.lookup("hello", at: files.mdx)
        #expect(entry?.word == "hello")
        #expect(entry?.html == html)
        let missing = try await store.lookup("absent", at: files.mdx)
        #expect(missing == nil)
    }

    @Test
    func preservesDuplicateHeadwordsInRecordOrder() async throws {
        let archive = try MDictFixture(entries: [("hello", Data("<p>first</p>".utf8)), ("hello", Data("<p>second</p>".utf8))])
        let files = try DictionaryFiles(archive: archive.data)
        defer { files.cleanup() }

        let entry = try await DictionaryStore().lookup("hello", at: files.mdx)
        let html = try #require(entry?.html)
        #expect(html.contains("<p>first</p>"))
        #expect(html.contains("<p>second</p>"))
        #expect(try #require(html.range(of: "first")).lowerBound < #require(html.range(of: "second")).lowerBound)
    }

    @Test
    func rejectsExcessiveDuplicateHeadwordExpansion() async throws {
        let entries = Array(repeating: ("hello", Data("<p>hello</p>".utf8)), count: 1_025)
        let archive = try MDictFixture(entries: entries)
        try await expectInvalidArchive(archive.data)
    }

    @Test
    func boundsSharedRecordBytesBeforeMaterializingDuplicates() async throws {
        let entries = Array(repeating: ("hello", Data(repeating: 65, count: 1_024 * 1_024)), count: 100)
        let archive = try MDictFixture(entries: entries, sharedRecord: true)
        try await expectInvalidArchive(archive.data)
    }

    @Test
    func limitsTotalRecordsAcrossRedirectBranches() async throws {
        let entries = Array(repeating: ("hello", Data("@@@LINK=world".utf8)), count: 16)
            + Array(repeating: ("world", Data("@@@LINK=final".utf8)), count: 16)
            + Array(repeating: ("final", Data("<p>final</p>".utf8)), count: 16)
        let archive = try MDictFixture(entries: entries)
        try await expectInvalidArchive(archive.data)
    }

    @Test
    func followsHeaderCaseAndStripKeyRules() async throws {
        let entries = [("co-operate", Data("<p>cooperate</p>".utf8))]
        let normalized = try DictionaryFiles(archive: MDictFixture(entries: entries).data)
        defer { normalized.cleanup() }
        let matched = try await DictionaryStore().lookup("CO OPERATE", at: normalized.mdx)
        #expect(matched?.html == "<p>cooperate</p>")

        let exact = try DictionaryFiles(archive: MDictFixture(entries: entries, caseSensitive: true, stripKey: false).data)
        defer { exact.cleanup() }
        let store = DictionaryStore()
        let wrongCase = try await store.lookup("CO-OPERATE", at: exact.mdx)
        let wrongPunctuation = try await store.lookup("cooperate", at: exact.mdx)
        let exactMatch = try await store.lookup("co-operate", at: exact.mdx)
        #expect(wrongCase == nil)
        #expect(wrongPunctuation == nil)
        #expect(exactMatch?.html == "<p>cooperate</p>")
    }

    @Test
    func readsUTF16DictionaryKeysAndHTML() async throws {
        let html = "<h1>你好</h1><p>A greeting 👋</p>"
        let archive = try MDictFixture(entries: [("你好", utf16LE(html))], encoding: "UTF-16")
        let files = try DictionaryFiles(archive: archive.data)
        defer { files.cleanup() }

        let entry = try await DictionaryStore().lookup("你好", at: files.mdx)
        #expect(entry?.word == "你好")
        #expect(entry?.html == html)
    }

    @Test
    func resolvesAliasesAndRejectsRedirectLoops() async throws {
        let archive = try MDictFixture(entries: [
            ("greeting", Data("@@@LINK=hello\r\n".utf8)),
            ("hello", Data("<p>hello</p>".utf8)),
            ("loop-a", Data("@@@LINK=loop-b".utf8)),
            ("loop-b", Data("@@@LINK=loop-a".utf8))
        ])
        let files = try DictionaryFiles(archive: archive.data)
        defer { files.cleanup() }
        let store = DictionaryStore()
        let entry = try await store.lookup("greeting", at: files.mdx)
        #expect(entry?.html == "<p>hello</p>")
        do {
            _ = try await store.lookup("loop-a", at: files.mdx)
            Issue.record("A dictionary redirect cycle must throw")
        } catch let error as DictionaryError {
            #expect(error == .redirectLoop)
        }
    }

    @Test
    func readsUTF16ResourceKeysAndPrefersExternalFiles() async throws {
        let archive = try MDictFixture(entries: [("hello", Data("<p>hello</p>".utf8))])
        let files = try DictionaryFiles(archive: archive.data)
        defer { files.cleanup() }
        let audio = Data([0x49, 0x44, 0x33, 0, 0xFF, 0x80])
        let resources = try MDictFixture(entries: [("\\style.css", Data("packed style".utf8))], resource: true)
        try resources.data.write(to: files.directory.appendingPathComponent("fixture.mdd"))
        let volume = try MDictFixture(entries: [("\\audio\\你好 us.mp3", audio)], resource: true)
        try volume.data.write(to: files.directory.appendingPathComponent("fixture.1.mdd"))
        try Data("external style".utf8).write(to: files.directory.appendingPathComponent("style.css"))

        let store = DictionaryStore()
        let entry = try await store.lookup("hello", at: files.root)
        let sound = try await store.resource("audio/%E4%BD%A0%E5%A5%BD%20us.mp3", at: files.root)
        let style = try await store.resource("style.css", at: files.root)
        let missing = try await store.resource("missing.png", at: files.root)
        #expect(entry?.html == "<p>hello</p>")
        #expect(sound == audio)
        #expect(style == Data("external style".utf8))
        #expect(missing == nil)
    }

    @Test
    func rejectsResourceTraversalAndSymlinkEscapes() async throws {
        let archive = try MDictFixture(entries: [("hello", Data("hello".utf8))])
        let files = try DictionaryFiles(archive: archive.data)
        defer { files.cleanup() }
        let secret = files.root.appendingPathComponent("private.txt")
        try Data("outside the selected dictionary".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: files.directory.appendingPathComponent("escape.txt"), withDestinationURL: secret)
        let store = DictionaryStore()
        for path in ["../private.txt", "%2E%2E/private.txt", "..\\private.txt", "escape.txt"] {
            do {
                _ = try await store.resource(path, at: files.mdx)
                Issue.record("Resource path escaped the dictionary folder: \(path)")
            } catch let error as DictionaryError {
                #expect(error == .invalidResourcePath)
            }
        }
    }

    @Test
    func validatesHeaderIndexKeyAndRecordChecksums() async throws {
        let archive = try MDictFixture(entries: [("hello", Data("<p>hello</p>".utf8))])
        for offset in [archive.headerChecksumOffset, archive.keyHeaderOffset + 40, archive.keyIndexChecksumOffset, archive.keyBlockChecksumOffset, archive.recordBlockChecksumOffset] {
            var damaged = archive.data
            damaged[offset] ^= 0x80
            try await expectInvalidArchive(damaged)
        }
    }

    @Test
    func rejectsTruncatedAndImpossibleLengths() async throws {
        let archive = try MDictFixture(entries: [("hello", Data("<p>hello</p>".utf8))])
        try await expectInvalidArchive(Data(archive.data.dropLast()))
        try await expectInvalidArchive(Data(archive.data.prefix(10)))

        var headerLength = archive.data
        headerLength.replaceSubrange(0..<4, with: integerBytes(UInt32.max))
        try await expectInvalidArchive(headerLength)

        var keyCount = archive.data
        keyCount.replaceSubrange(archive.keyHeaderOffset..<(archive.keyHeaderOffset + 8), with: integerBytes(UInt64.max))
        let header = keyCount.subdata(in: archive.keyHeaderOffset..<(archive.keyHeaderOffset + 40))
        keyCount.replaceSubrange((archive.keyHeaderOffset + 40)..<(archive.keyHeaderOffset + 44), with: integerBytes(checksum(header)))
        try await expectInvalidArchive(keyCount)

        var recordIndexLength = archive.data
        recordIndexLength.replaceSubrange((archive.recordHeaderOffset + 16)..<(archive.recordHeaderOffset + 24), with: integerBytes(UInt64.max))
        try await expectInvalidArchive(recordIndexLength)
    }

    @Test
    func reportsUnsupportedFormatsExplicitly() async throws {
        let entries = [("hello", Data("hello".utf8))]
        let variants: [(MDictFixture, DictionaryError)] = [
            (try MDictFixture(entries: entries, version: "1.2"), .unsupportedVersion),
            (try MDictFixture(entries: entries, encrypted: "1"), .encryptedArchive),
            (try MDictFixture(entries: entries, encoding: "GBK"), .unsupportedEncoding)
        ]
        for (archive, expected) in variants {
            try await expectFailure(expected, archive: archive.data)
        }
        let archive = try MDictFixture(entries: entries)
        var lzo = archive.data
        lzo[archive.keyIndexChecksumOffset - 4] = 1
        try await expectFailure(.unsupportedCompression, archive: lzo)
    }

    @Test
    func installedOxfordDictionaryIncludesHelloAndRecordedAudio() async throws {
        let mdx = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Dictionary/OALDPEX-Final/oaldpex.mdx")
        guard FileManager.default.fileExists(atPath: mdx.path) else { return }
        let store = DictionaryStore()
        let entry = try #require(await store.lookup("hello", at: mdx))
        #expect(entry.html.localizedCaseInsensitiveContains("hello"))
        let expression = try NSRegularExpression(pattern: #"sound://([^"'<>]+)"#, options: .caseInsensitive)
        let match = try #require(expression.firstMatch(in: entry.html, range: NSRange(entry.html.startIndex..., in: entry.html)))
        let range = try #require(Range(match.range(at: 1), in: entry.html))
        let audio = try #require(await store.resource(String(entry.html[range]), at: mdx))
        #expect(!audio.isEmpty)
    }

    private func expectInvalidArchive(_ archive: Data) async throws {
        try await expectFailure(.invalidArchive, archive: archive)
    }

    private func expectFailure(_ expected: DictionaryError, archive: Data) async throws {
        let files = try DictionaryFiles(archive: archive)
        defer { files.cleanup() }
        do {
            _ = try await DictionaryStore().lookup("hello", at: files.mdx)
            Issue.record("An invalid dictionary archive must throw \(expected)")
        } catch let error as DictionaryError {
            #expect(error == expected)
        }
    }
}

private struct DictionaryFiles {
    let root: URL
    let directory: URL
    let mdx: URL

    init(archive: Data) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("VellumMDict-\(UUID().uuidString)", isDirectory: true)
        directory = root.appendingPathComponent("dictionary", isDirectory: true)
        mdx = directory.appendingPathComponent("fixture.mdx")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try archive.write(to: mdx)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

// Synthetic v2 layout: https://github.com/zhansliu/writemdict/blob/master/fileformat.md
private struct MDictFixture {
    var data: Data
    let headerChecksumOffset: Int
    let keyHeaderOffset: Int
    let keyIndexChecksumOffset: Int
    let keyBlockChecksumOffset: Int
    let recordHeaderOffset: Int
    let recordBlockChecksumOffset: Int

    init(entries: [(String, Data)], resource: Bool = false, compressed: Bool = true, splitAt: Int? = nil, caseSensitive: Bool = false, stripKey: Bool = true, version: String = "2.0", encrypted: String = "No", encoding: String = "UTF-8", sharedRecord: Bool = false) throws {
        let tag = resource ? "Library_Data" : "Dictionary"
        let xml = "<\(tag) GeneratedByEngineVersion=\"\(version)\" RequiredEngineVersion=\"\(version)\" Encrypted=\"\(encrypted)\" Encoding=\"\(encoding)\" Format=\"Html\" KeyCaseSensitive=\"\(caseSensitive ? "Yes" : "No")\" StripKey=\"\(stripKey ? "Yes" : "No")\" Title=\"Vellum fixture\"/>"
        let header = utf16LE(xml + "\0")
        data = integerBytes(UInt32(header.count)) + header
        headerChecksumOffset = data.count
        data += integerBytes(checksum(header).littleEndian, bigEndian: false)

        var keys = Data()
        var records = Data()
        let wideEncoding = resource || encoding.uppercased().replacingOccurrences(of: "-", with: "") == "UTF16"
        for (word, body) in entries {
            keys += integerBytes(UInt64(sharedRecord ? 0 : records.count))
            keys += wideEncoding ? utf16LE(word + "\0") : Data((word + "\0").utf8)
            if sharedRecord, !records.isEmpty { continue }
            records += body
            if !resource { records += wideEncoding ? Data([0, 0]) : Data([0]) }
        }
        let keyBlock = try packet(keys, compressed: compressed)
        var index = integerBytes(UInt64(entries.count))
        for word in [entries.first?.0 ?? "", entries.last?.0 ?? ""] {
            let encoded = wideEncoding ? utf16LE(word) : Data(word.utf8)
            index += integerBytes(UInt16(wideEncoding ? word.utf16.count : encoded.count))
            index += encoded
            index += wideEncoding ? Data([0, 0]) : Data([0])
        }
        index += integerBytes(UInt64(keyBlock.count))
        index += integerBytes(UInt64(keys.count))
        let indexBlock = try packet(index, compressed: compressed)
        keyHeaderOffset = data.count
        let keyHeader = [UInt64(1), UInt64(entries.count), UInt64(index.count), UInt64(indexBlock.count), UInt64(keyBlock.count)].reduce(into: Data()) { $0 += integerBytes($1) }
        data += keyHeader + integerBytes(checksum(keyHeader))
        keyIndexChecksumOffset = data.count + 4
        data += indexBlock
        keyBlockChecksumOffset = data.count + 4
        data += keyBlock

        let recordParts: [Data]
        if let splitAt {
            recordParts = [Data(records.prefix(splitAt)), Data(records.dropFirst(splitAt))]
        } else {
            recordParts = [records]
        }
        let recordBlocks = try recordParts.map { try packet($0, compressed: compressed) }
        recordHeaderOffset = data.count
        for value in [UInt64(recordBlocks.count), UInt64(entries.count), UInt64(recordBlocks.count * 16), UInt64(recordBlocks.reduce(0) { $0 + $1.count })] {
            data += integerBytes(value)
        }
        for (part, block) in zip(recordParts, recordBlocks) {
            data += integerBytes(UInt64(block.count))
            data += integerBytes(UInt64(part.count))
        }
        recordBlockChecksumOffset = data.count + 4
        for block in recordBlocks { data += block }
    }
}

private func integerBytes<T: FixedWidthInteger>(_ value: T, bigEndian: Bool = true) -> Data {
    var encoded = bigEndian ? value.bigEndian : value
    return withUnsafeBytes(of: &encoded) { Data($0) }
}

private func utf16LE(_ value: String) -> Data {
    value.utf16.reduce(into: Data()) { $0 += integerBytes($1.littleEndian, bigEndian: false) }
}

private func checksum(_ value: Data) -> UInt32 {
    value.withUnsafeBytes { UInt32(adler32(1, $0.bindMemory(to: Bytef.self).baseAddress, uInt(value.count))) }
}

private func packet(_ value: Data, compressed: Bool) throws -> Data {
    var result = Data([compressed ? 2 : 0, 0, 0, 0]) + integerBytes(checksum(value))
    guard compressed else { return result + value }
    var length = compressBound(uLong(value.count))
    var output = Data(count: Int(length))
    let status = output.withUnsafeMutableBytes { destination in
        value.withUnsafeBytes { source in
            compress2(destination.bindMemory(to: Bytef.self).baseAddress, &length, source.bindMemory(to: Bytef.self).baseAddress, uLong(value.count), Z_DEFAULT_COMPRESSION)
        }
    }
    #expect(status == Z_OK)
    output.count = Int(length)
    result += output
    return result
}

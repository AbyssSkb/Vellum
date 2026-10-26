import Foundation
import Testing
import zlib
@testable import VellumCore

@Suite("MDict record decompression budget")
struct MDictRecordBudgetTests {
    @Test
    func rejectsCumulativeCompressedResourceExpansion() throws {
        let fixture = try resourceBlocks(blockSize: 16 * 1_024 * 1_024, blockCount: 8)
        #expect(fixture.count < 200_000)
        try withRecordArchive(fixture) { archive in
            var budget = MDictArchive.ReadBudget()
            #expect(throws: DictionaryError.invalidArchive) {
                _ = try archive.entries(for: "audio.mp3", budget: &budget)
            }
        }
    }

    @Test
    func permitsOutputAndDecompressionAtTheirSeparateLimits() throws {
        let fixture = try resourceBlocks(blockSize: 4_096, blockCount: 2)
        try withRecordArchive(fixture) { archive in
            var budget = MDictArchive.ReadBudget(bytes: 2, decompressedBytes: 8_192)
            let entries = try archive.entries(for: "audio.mp3", budget: &budget)
            #expect(entries.map(\.data) == [Data([65]), Data([65])])
            #expect(budget.bytes == 0)
            #expect(budget.decompressedBytes == 0)
        }
    }

    @Test
    func checksCumulativeDeclaredSizeBeforeDecodingTheNextBlock() throws {
        let fixture = try resourceBlocks(blockSize: 4_096, blockCount: 2, unsupportedLastBlock: true)
        try withRecordArchive(fixture) { archive in
            var budget = MDictArchive.ReadBudget(decompressedBytes: 8_191)
            #expect(throws: DictionaryError.invalidArchive) {
                _ = try archive.entries(for: "audio.mp3", budget: &budget)
            }
            #expect(budget.decompressedBytes == 4_095)
        }
    }

    @Test
    func sharesDecompressionBudgetAcrossReadsAndChargesEvictedBlocksAgain() throws {
        let fixture = try resourceBlocks(blockSize: 4_096, blockCount: 2)
        try withRecordArchive(fixture) { archive in
            var budget = MDictArchive.ReadBudget(decompressedBytes: 8_192)
            let first = try archive.entries(for: "filler-0", budget: &budget)
            #expect(first.first?.data.count == 4_095)
            #expect(budget.decompressedBytes == 4_096)
            let cached = try archive.entries(for: "filler-0", budget: &budget)
            #expect(cached.first?.data.count == 4_095)
            #expect(budget.decompressedBytes == 4_096)
            let second = try archive.entries(for: "filler-1", budget: &budget)
            #expect(second.first?.data.count == 4_095)
            #expect(budget.decompressedBytes == 0)
            #expect(throws: DictionaryError.invalidArchive) {
                _ = try archive.entries(for: "filler-0", budget: &budget)
            }
        }
    }

    @Test
    func readsWarmCacheWithoutDecompressionBudget() throws {
        let fixture = try resourceBlocks(blockSize: 4_096, blockCount: 1)
        try withRecordArchive(fixture) { archive in
            var initialBudget = MDictArchive.ReadBudget()
            _ = try archive.entries(for: "audio.mp3", budget: &initialBudget)
            var budget = MDictArchive.ReadBudget(decompressedBytes: 0)
            #expect(try archive.entries(for: "audio.mp3", budget: &budget).first?.data == Data([65]))
            #expect(budget.decompressedBytes == 0)
        }
    }
}

private func withRecordArchive(_ data: Data, body: (MDictArchive) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("VellumRecordBudget-\(UUID().uuidString).mdd")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(MDictArchive(url: url, isResource: true))
}

private func resourceBlocks(blockSize: Int, blockCount: Int, unsupportedLastBlock: Bool = false) throws -> Data {
    let xml = "<Library_Data GeneratedByEngineVersion=\"2.0\" Encoding=\"UTF-16\"/>"
    let header = try #require((xml + "\0").data(using: .utf16LittleEndian))
    var data = recordInteger(UInt32(header.count)) + header + recordInteger(recordChecksum(header), littleEndian: true)
    var keys = Data()
    for index in 0..<blockCount {
        for (offset, word) in [(index * blockSize, index.isMultiple(of: 2) ? "\\audio.mp3" : "/AUDIO.MP3"),
                               (index * blockSize + 1, "filler-\(index)")] {
            keys += recordInteger(UInt64(offset))
            keys += try #require((word + "\0").data(using: .utf16LittleEndian))
        }
    }
    let keyBlock = try recordPacket(keys)
    var keyIndex = recordInteger(UInt64(blockCount * 2))
    for _ in 0..<2 {
        keyIndex += recordInteger(UInt16(1)) + Data([97, 0, 0, 0])
    }
    keyIndex += recordInteger(UInt64(keyBlock.count)) + recordInteger(UInt64(keys.count))
    let keyIndexBlock = try recordPacket(keyIndex)
    let keyHeader = [1, blockCount * 2, keyIndex.count, keyIndexBlock.count, keyBlock.count]
        .reduce(into: Data()) { $0 += recordInteger(UInt64($1)) }
    data += keyHeader + recordInteger(recordChecksum(keyHeader)) + keyIndexBlock + keyBlock

    let block = try recordPacket(Data(repeating: 65, count: blockSize))
    for value in [blockCount, blockCount * 2, blockCount * 16, block.count * blockCount] {
        data += recordInteger(UInt64(value))
    }
    for _ in 0..<blockCount {
        data += recordInteger(UInt64(block.count)) + recordInteger(UInt64(blockSize))
    }
    for index in 0..<blockCount {
        var packet = block
        if unsupportedLastBlock, index == blockCount - 1 { packet[0] = 1 }
        data += packet
    }
    return data
}

private func recordInteger<T: FixedWidthInteger>(_ value: T, littleEndian: Bool = false) -> Data {
    var encoded = littleEndian ? value.littleEndian : value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}

private func recordChecksum(_ value: Data) -> UInt32 {
    value.withUnsafeBytes { UInt32(adler32(1, $0.bindMemory(to: Bytef.self).baseAddress, uInt(value.count))) }
}

private func recordPacket(_ value: Data) throws -> Data {
    var length = compressBound(uLong(value.count))
    var output = Data(count: Int(length))
    let status = output.withUnsafeMutableBytes { destination in
        value.withUnsafeBytes { source in
            compress2(destination.bindMemory(to: Bytef.self).baseAddress, &length,
                      source.bindMemory(to: Bytef.self).baseAddress, uLong(value.count), Z_DEFAULT_COMPRESSION)
        }
    }
    #expect(status == Z_OK)
    output.count = Int(length)
    return Data([2, 0, 0, 0]) + recordInteger(recordChecksum(value)) + output
}

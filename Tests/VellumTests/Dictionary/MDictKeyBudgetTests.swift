import Foundation
import Testing
import zlib
@testable import VellumCore

@Suite("MDict key table budget")
struct MDictKeyBudgetTests {
    @Test
    func rejectsCumulativeCompressedKeyExpansion() throws {
        let archive = try keyTableArchive(blockSize: 48 * 1_024 * 1_024, blockCount: 3)
        #expect(archive.count < 200_000)
        try withArchive(archive) { url in
            #expect(throws: DictionaryError.invalidArchive) {
                _ = try MDictArchive(url: url)
            }
        }
    }

    @Test
    func checksDeclaredTotalBeforeDecompressingAnyKeyBlock() throws {
        let archive = try keyTableArchive(blockSize: 48 * 1_024 * 1_024, blockCount: 3, unsupportedFirstBlock: true)
        try withArchive(archive) { url in
            #expect(throws: DictionaryError.invalidArchive) {
                _ = try MDictArchive(url: url)
            }
        }
    }

    @Test
    func permitsMultipleKeyBlocksWithinBudget() throws {
        let archive = try keyTableArchive(blockSize: 1_024, blockCount: 3)
        try withArchive(archive) { url in
            let dictionary = try MDictArchive(url: url)
            var budget = MDictArchive.ReadBudget()
            let entries = try dictionary.entries(for: String(repeating: "a", count: 1_015), budget: &budget)
            #expect(entries.count == 3)
        }
    }
}

private func withArchive(_ data: Data, body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("VellumKeyBudget-\(UUID().uuidString).mdx")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

private func keyTableArchive(blockSize: Int, blockCount: Int, unsupportedFirstBlock: Bool = false) throws -> Data {
    let xml = "<Dictionary GeneratedByEngineVersion=\"2.0\" Encoding=\"UTF-8\" KeyCaseSensitive=\"Yes\" StripKey=\"No\"/>"
    let header = try #require((xml + "\0").data(using: .utf16LittleEndian))
    var data = keyInteger(UInt32(header.count)) + header + keyInteger(keyChecksum(header), littleEndian: true)
    var key = Data(repeating: 97, count: blockSize)
    key.replaceSubrange(0..<8, with: Data(repeating: 0, count: 8))
    key[blockSize - 1] = 0
    let block = try keyPacket(key)
    var index = Data()
    for _ in 0..<blockCount {
        index += keyInteger(UInt64(1))
        for _ in 0..<2 {
            index += keyInteger(UInt16(1)) + Data([97, 0])
        }
        index += keyInteger(UInt64(block.count)) + keyInteger(UInt64(blockSize))
    }
    let indexPacket = try keyPacket(index)
    let keyHeader = [blockCount, blockCount, index.count, indexPacket.count, block.count * blockCount]
        .reduce(into: Data()) { $0 += keyInteger(UInt64($1)) }
    data += keyHeader + keyInteger(keyChecksum(keyHeader)) + indexPacket
    for ordinal in 0..<blockCount {
        var packet = block
        if ordinal == 0, unsupportedFirstBlock { packet[0] = 1 }
        data += packet
    }
    let record = try keyPacket(Data([120]))
    for value in [1, blockCount, 16, record.count, record.count, 1] {
        data += keyInteger(UInt64(value))
    }
    data += record
    return data
}

private func keyInteger<T: FixedWidthInteger>(_ value: T, littleEndian: Bool = false) -> Data {
    var encoded = littleEndian ? value.littleEndian : value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}

private func keyChecksum(_ value: Data) -> UInt32 {
    value.withUnsafeBytes { UInt32(adler32(1, $0.bindMemory(to: Bytef.self).baseAddress, uInt(value.count))) }
}

private func keyPacket(_ value: Data) throws -> Data {
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
    return Data([2, 0, 0, 0]) + keyInteger(keyChecksum(value)) + output
}

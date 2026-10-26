import Foundation
import zlib

public enum DictionaryError: Error, Equatable {
    case dictionaryNotFound
    case unsupportedVersion
    case encryptedArchive
    case unsupportedEncoding
    case unsupportedCompression
    case invalidArchive
    case invalidResourcePath
    case redirectLoop
    case unreadableFile
}

// v2 layout: https://github.com/zhansliu/writemdict/blob/master/fileformat.md
final class MDictArchive {
    struct ReadBudget {
        var records = 1_024
        var bytes = 64 * 1_024 * 1_024
        var decompressedBytes = 64 * 1_024 * 1_024
    }

    private struct Key {
        let text: String
        let offset: Int
        var end: Int = 0
    }

    private struct Block {
        let fileOffset: Int
        let compressedSize: Int
        let offset: Int
        let size: Int
    }

    private let file: FileHandle
    private let fileSize: Int
    private let encoding: String.Encoding
    private let caseSensitive: Bool
    private let stripKey: Bool
    private let isResource: Bool
    private var keys: [Key] = []
    private var exactKeys: [String: [Int]] = [:]
    private var normalizedKeys: [String: [Int]] = [:]
    private var blocks: [Block] = []
    private var cachedBlock: (index: Int, data: Data)?

    private static let maximumBlockSize = 64 * 1_024 * 1_024
    private static let maximumIndexSize = 128 * 1_024 * 1_024
    private static let ignoredKeyCharacters = CharacterSet(charactersIn: "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ ")
        .union(.whitespacesAndNewlines)

    init(url: URL, isResource: Bool = false) throws {
        do {
            file = try FileHandle(forReadingFrom: url)
            let size = try file.seekToEnd()
            guard let size = Int(exactly: size) else { throw DictionaryError.invalidArchive }
            fileSize = size
        } catch let error as DictionaryError {
            throw error
        } catch {
            throw DictionaryError.unreadableFile
        }
        self.isResource = isResource

        var length = BinaryReader(try Self.read(file, fileSize: fileSize, offset: 0, count: 4))
        let headerLength = try length.number(4)
        guard headerLength > 0, headerLength <= 16 * 1_024 * 1_024 else { throw DictionaryError.invalidArchive }
        let headerData = try Self.read(file, fileSize: fileSize, offset: 4, count: headerLength)
        var headerChecksum = BinaryReader(try Self.read(file, fileSize: fileSize, offset: 4 + headerLength, count: 4))
        guard try headerChecksum.number(4, littleEndian: true) == Self.checksum(headerData),
              let header = String(data: headerData, encoding: .utf16LittleEndian) else {
            throw DictionaryError.invalidArchive
        }
        let attributes = Self.attributes(in: header)
        guard attributes["generatedbyengineversion"]?.split(separator: ".").first == "2" else {
            throw DictionaryError.unsupportedVersion
        }
        let encrypted = attributes["encrypted", default: "No"].lowercased()
        guard encrypted == "no" || encrypted == "0" else { throw DictionaryError.encryptedArchive }
        let declaredEncoding = attributes["encoding", default: "UTF-8"]
            .uppercased().replacingOccurrences(of: "-", with: "")
        if isResource || declaredEncoding == "UTF16" {
            encoding = .utf16LittleEndian
        } else if declaredEncoding == "UTF8" {
            encoding = .utf8
        } else {
            throw DictionaryError.unsupportedEncoding
        }
        caseSensitive = attributes["keycasesensitive"]?.lowercased() == "yes"
        stripKey = !isResource && attributes["stripkey"]?.lowercased() == "yes"

        var position = 8 + headerLength
        let keyHeaderData = try read(offset: position, count: 40)
        var keyHeader = BinaryReader(keyHeaderData)
        let keyBlockCount = try keyHeader.number(8)
        let entryCount = try keyHeader.number(8)
        let keyIndexSize = try keyHeader.number(8)
        let keyIndexCompressedSize = try keyHeader.number(8)
        let keyBlocksSize = try keyHeader.number(8)
        position += 40
        var keyChecksum = BinaryReader(try read(offset: position, count: 4))
        guard try keyChecksum.number(4) == Self.checksum(keyHeaderData),
              keyBlockCount <= fileSize / 8, entryCount <= 5_000_000,
              keyIndexSize <= Self.maximumIndexSize, keyIndexCompressedSize <= Self.maximumIndexSize else {
            throw DictionaryError.invalidArchive
        }
        position += 4
        var index = BinaryReader(try decode(offset: position, compressedSize: keyIndexCompressedSize, size: keyIndexSize))
        position += keyIndexCompressedSize
        let keyBlocksStart = position
        let width = encoding == .utf16LittleEndian ? 2 : 1
        var keyBlocks: [(count: Int, compressedSize: Int, size: Int)] = []
        var keyCount = 0
        var keyTableSize = 0
        for _ in 0..<keyBlockCount {
            let count = try index.number(8)
            let firstLength = try index.number(2)
            try index.skip((firstLength + 1) * width)
            let lastLength = try index.number(2)
            try index.skip((lastLength + 1) * width)
            let compressedSize = try index.number(8)
            let size = try index.number(8)
            guard count <= entryCount - keyCount,
                  size <= Self.maximumIndexSize - keyTableSize else { throw DictionaryError.invalidArchive }
            keyCount += count
            keyTableSize += size
            keyBlocks.append((count, compressedSize, size))
        }
        guard index.isAtEnd, keyCount == entryCount else { throw DictionaryError.invalidArchive }
        keys.reserveCapacity(entryCount)
        for block in keyBlocks {
            var keyBlock = BinaryReader(try decode(offset: position, compressedSize: block.compressedSize, size: block.size))
            position = try Self.add(position, block.compressedSize)
            for _ in 0..<block.count {
                let offset = try keyBlock.number(8)
                let text = try keyBlock.string(encoding: encoding, width: width)
                guard keys.last.map({ $0.offset <= offset }) ?? true else { throw DictionaryError.invalidArchive }
                keys.append(Key(text: text, offset: offset))
            }
            guard keyBlock.isAtEnd else { throw DictionaryError.invalidArchive }
        }
        guard position - keyBlocksStart == keyBlocksSize else { throw DictionaryError.invalidArchive }

        var recordHeader = BinaryReader(try read(offset: position, count: 32))
        let recordBlockCount = try recordHeader.number(8)
        let recordEntryCount = try recordHeader.number(8)
        let recordIndexSize = try recordHeader.number(8)
        let recordBlocksSize = try recordHeader.number(8)
        guard recordBlockCount <= Self.maximumIndexSize / 16,
              recordEntryCount == entryCount, recordIndexSize == recordBlockCount * 16 else {
            throw DictionaryError.invalidArchive
        }
        position += 32
        var recordIndex = BinaryReader(try read(offset: position, count: recordIndexSize))
        position += recordIndexSize
        let recordBlocksStart = position
        var recordOffset = 0
        for _ in 0..<recordBlockCount {
            let compressedSize = try recordIndex.number(8)
            let size = try recordIndex.number(8)
            guard compressedSize >= 8, compressedSize <= Self.maximumBlockSize,
                  size > 0, size <= Self.maximumBlockSize else { throw DictionaryError.invalidArchive }
            let end = try Self.add(position, compressedSize)
            guard end <= fileSize else { throw DictionaryError.invalidArchive }
            blocks.append(Block(fileOffset: position, compressedSize: compressedSize, offset: recordOffset, size: size))
            position = end
            recordOffset = try Self.add(recordOffset, size)
        }
        guard position - recordBlocksStart == recordBlocksSize,
              keys.last.map({ $0.offset <= recordOffset }) ?? true else { throw DictionaryError.invalidArchive }
        var recordEnd = recordOffset
        for ordinal in keys.indices.reversed() {
            if ordinal + 1 < keys.count, keys[ordinal].offset < keys[ordinal + 1].offset {
                recordEnd = keys[ordinal + 1].offset
            }
            keys[ordinal].end = recordEnd
        }
        for (ordinal, key) in keys.enumerated() {
            if !isResource { exactKeys[key.text, default: []].append(ordinal) }
            normalizedKeys[normalize(key.text), default: []].append(ordinal)
        }
    }

    deinit { try? file.close() }

    func entries(for text: String, budget: inout ReadBudget) throws -> [(word: String, data: Data)] {
        let ordinals = exactKeys[text] ?? normalizedKeys[normalize(text)] ?? []
        guard ordinals.count <= budget.records else { throw DictionaryError.invalidArchive }
        budget.records -= ordinals.count
        for ordinal in ordinals {
            let size = keys[ordinal].end - keys[ordinal].offset
            guard size <= budget.bytes else { throw DictionaryError.invalidArchive }
            budget.bytes -= size
        }
        return try ordinals.map { (keys[$0].text, try record(at: $0, budget: &budget)) }
    }

    func text(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: encoding) else { throw DictionaryError.invalidArchive }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private func normalize(_ text: String) -> String {
        if isResource {
            return text.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        let text = caseSensitive ? text : text.lowercased()
        return stripKey ? String(text.unicodeScalars.filter { !Self.ignoredKeyCharacters.contains($0) }) : text
    }

    private func record(at ordinal: Int, budget: inout ReadBudget) throws -> Data {
        let key = keys[ordinal]
        guard key.end - key.offset <= Self.maximumBlockSize else { throw DictionaryError.invalidArchive }
        var result = Data()
        result.reserveCapacity(key.end - key.offset)
        var lower = 0
        var upper = blocks.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if blocks[middle].offset + blocks[middle].size <= key.offset { lower = middle + 1 }
            else { upper = middle }
        }
        var index = lower
        while index < blocks.count, blocks[index].offset < key.end {
            let block = blocks[index]
            let data: Data
            if let cachedBlock, cachedBlock.index == index {
                data = cachedBlock.data
            } else {
                guard block.size <= budget.decompressedBytes else { throw DictionaryError.invalidArchive }
                budget.decompressedBytes -= block.size
                data = try decode(offset: block.fileOffset, compressedSize: block.compressedSize, size: block.size)
                cachedBlock = (index, data)
            }
            let start = max(key.offset, block.offset) - block.offset
            let end = min(key.end, block.offset + block.size) - block.offset
            result.append(data[start..<end])
            index += 1
        }
        guard result.count == key.end - key.offset else { throw DictionaryError.invalidArchive }
        return result
    }

    private func read(offset: Int, count: Int) throws -> Data {
        try Self.read(file, fileSize: fileSize, offset: offset, count: count)
    }

    private static func read(_ file: FileHandle, fileSize: Int, offset: Int, count: Int) throws -> Data {
        guard offset >= 0, offset <= fileSize, count >= 0, count <= fileSize - offset,
              count <= maximumIndexSize else { throw DictionaryError.invalidArchive }
        do {
            try file.seek(toOffset: UInt64(offset))
            guard let data = try file.read(upToCount: count), data.count == count else {
                if count == 0 { return Data() }
                throw DictionaryError.invalidArchive
            }
            return data
        } catch let error as DictionaryError {
            throw error
        } catch {
            throw DictionaryError.unreadableFile
        }
    }

    private func decode(offset: Int, compressedSize: Int, size: Int) throws -> Data {
        guard compressedSize >= 8, size >= 0, size <= Self.maximumIndexSize,
              compressedSize <= Self.maximumIndexSize else { throw DictionaryError.invalidArchive }
        let packet = try read(offset: offset, count: compressedSize)
        var header = BinaryReader(packet)
        let compression = try header.number(4, littleEndian: true)
        let checksum = try header.number(4)
        let payload = Data(packet.dropFirst(8))
        let result: Data
        switch compression {
        case 0:
            guard payload.count == size else { throw DictionaryError.invalidArchive }
            result = payload
        case 2:
            var output = Data(count: max(size, 1))
            var outputLength = uLong(size)
            var sourceLength = uLong(payload.count)
            let status = output.withUnsafeMutableBytes { destination in
                payload.withUnsafeBytes { source in
                    uncompress2(destination.bindMemory(to: Bytef.self).baseAddress, &outputLength,
                                source.bindMemory(to: Bytef.self).baseAddress, &sourceLength)
                }
            }
            guard status == Z_OK, outputLength == size, sourceLength == payload.count else {
                throw DictionaryError.invalidArchive
            }
            result = Data(output.prefix(size))
        default:
            throw DictionaryError.unsupportedCompression
        }
        guard Self.checksum(result) == checksum else { throw DictionaryError.invalidArchive }
        return result
    }

    private static func checksum(_ data: Data) -> Int {
        data.withUnsafeBytes { Int(adler32(1, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }

    private static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw DictionaryError.invalidArchive }
        return value
    }

    private static func attributes(in header: String) -> [String: String] {
        let expression = try! NSRegularExpression(pattern: "([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*\"([^\"]*)\"")
        let string = header as NSString
        return expression.matches(in: header, range: NSRange(location: 0, length: string.length))
            .reduce(into: [:]) { result, match in
                result[string.substring(with: match.range(at: 1)).lowercased()] = string.substring(with: match.range(at: 2))
            }
    }
}

private struct BinaryReader {
    let data: Data
    var offset = 0

    init(_ data: Data) { self.data = data }
    var isAtEnd: Bool { offset == data.count }

    mutating func number(_ width: Int, littleEndian: Bool = false) throws -> Int {
        guard width <= data.count - offset else { throw DictionaryError.invalidArchive }
        var value: UInt64 = 0
        for index in 0..<width {
            let byte = data[offset + (littleEndian ? width - index - 1 : index)]
            value = (value << 8) | UInt64(byte)
        }
        offset += width
        guard let result = Int(exactly: value) else { throw DictionaryError.invalidArchive }
        return result
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, count <= data.count - offset else { throw DictionaryError.invalidArchive }
        offset += count
    }

    mutating func string(encoding: String.Encoding, width: Int) throws -> String {
        let start = offset
        while width <= data.count - offset {
            if data[offset] == 0 && (width == 1 || data[offset + 1] == 0) {
                guard let result = String(data: data.subdata(in: start..<offset), encoding: encoding) else {
                    throw DictionaryError.invalidArchive
                }
                offset += width
                return result
            }
            offset += width
        }
        throw DictionaryError.invalidArchive
    }
}

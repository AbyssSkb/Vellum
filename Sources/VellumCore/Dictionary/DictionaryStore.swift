import Foundation

public struct DictionaryEntry: Sendable {
    public let word: String
    public let html: String
}

public actor DictionaryStore {
    public static let shared = DictionaryStore()

    private struct OpenDictionary {
        let location: URL
        let url: URL
        let archive: MDictArchive
        let resourceURLs: [URL]
        var resources: [URL: MDictArchive] = [:]
    }

    private var current: OpenDictionary?

    public init() {}

    public func invalidate() {
        current = nil
    }

    public func requestAccess(at location: URL) {
        guard location.isFileURL, location.pathExtension.lowercased() == "mdx",
              current?.location != location.standardizedFileURL else { return }
        // Resolve folder consent before lookup installs focus-dismiss observers; lookup reports access failures.
        _ = try? FileManager.default.contentsOfDirectory(
            at: location.resolvingSymlinksInPath().deletingLastPathComponent(), includingPropertiesForKeys: nil
        )
    }

    public func lookup(_ text: String, at location: URL) throws -> DictionaryEntry? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        try open(at: location)
        guard let archive = current?.archive else { throw DictionaryError.dictionaryNotFound }
        var budget = MDictArchive.ReadBudget()
        var remainingHTMLBytes = 64 * 1_024 * 1_024
        let entries = try lookup(word, in: archive, visited: [], budget: &budget, remainingHTMLBytes: &remainingHTMLBytes)
        guard let first = entries.first else { return nil }
        return DictionaryEntry(word: first.word, html: entries.map(\.html).joined(separator: "\n"))
    }

    public func resource(_ path: String, at location: URL) throws -> Data? {
        let path = try Self.resourcePath(path)
        try open(at: location)
        guard let dictionary = current else { throw DictionaryError.dictionaryNotFound }
        let root = dictionary.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let external = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard external.path.hasPrefix(root.path + "/") else { throw DictionaryError.invalidResourcePath }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: external.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            do {
                let size = try external.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64 * 1_024 * 1_024 else { throw DictionaryError.invalidArchive }
                return try Data(contentsOf: external)
            } catch let error as DictionaryError {
                throw error
            } catch {
                throw DictionaryError.unreadableFile
            }
        }
        for url in dictionary.resourceURLs {
            let archive: MDictArchive
            if let opened = current?.resources[url] {
                archive = opened
            } else {
                archive = try MDictArchive(url: url, isResource: true)
                current?.resources[url] = archive
            }
            var budget = MDictArchive.ReadBudget()
            if let data = try archive.entries(for: path, budget: &budget).first?.data { return data }
        }
        return nil
    }

    private func lookup(_ word: String, in archive: MDictArchive, visited: Set<String>,
                        budget: inout MDictArchive.ReadBudget, remainingHTMLBytes: inout Int) throws -> [DictionaryEntry] {
        guard visited.count < 32, !visited.contains(word) else { throw DictionaryError.redirectLoop }
        var visited = visited
        visited.insert(word)
        var result: [DictionaryEntry] = []
        for entry in try archive.entries(for: word, budget: &budget) {
            let html = try archive.text(from: entry.data)
            if html.hasPrefix("@@@LINK=") {
                let target = String(html.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(contentsOf: try lookup(target, in: archive, visited: visited,
                                                    budget: &budget, remainingHTMLBytes: &remainingHTMLBytes))
            } else {
                let size = html.utf8.count + 1
                guard size <= remainingHTMLBytes else { throw DictionaryError.invalidArchive }
                remainingHTMLBytes -= size
                result.append(DictionaryEntry(word: entry.word, html: html))
            }
        }
        return result
    }

    private func open(at location: URL) throws {
        let location = location.standardizedFileURL
        if current?.location == location { return }
        let url = try Self.dictionaryURL(at: location)
        let archive = try MDictArchive(url: url)
        let stem = url.deletingPathExtension().lastPathComponent
        let root = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let siblings: [URL]
        do {
            siblings = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        } catch {
            throw DictionaryError.unreadableFile
        }
        let resourceURLs = siblings.compactMap { candidate -> (Int, URL)? in
            guard candidate.pathExtension.lowercased() == "mdd",
                  candidate.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.path + "/") else { return nil }
            let name = candidate.deletingPathExtension().lastPathComponent
            if name.caseInsensitiveCompare(stem) == .orderedSame { return (0, candidate) }
            let prefix = stem + "."
            guard name.lowercased().hasPrefix(prefix.lowercased()),
                  let volume = Int(name.dropFirst(prefix.count)), volume > 0 else { return nil }
            return (volume, candidate)
        }.sorted { $0.0 == $1.0 ? $0.1.path < $1.1.path : $0.0 < $1.0 }.map(\.1)
        current = OpenDictionary(location: location, url: url, archive: archive, resourceURLs: resourceURLs)
    }

    private static func dictionaryURL(at location: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard location.isFileURL, location.pathExtension.lowercased() == "mdx",
              FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw DictionaryError.dictionaryNotFound
        }
        return location.resolvingSymlinksInPath()
    }

    private static func resourcePath(_ path: String) throws -> String {
        guard let decoded = path.removingPercentEncoding,
              !decoded.contains("\0"), !decoded.contains(":") else { throw DictionaryError.invalidResourcePath }
        let components = decoded.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard !components.contains("..") else { throw DictionaryError.invalidResourcePath }
        let relative = components.filter { $0 != "." }.joined(separator: "/")
        guard !relative.isEmpty else { throw DictionaryError.invalidResourcePath }
        return relative
    }
}

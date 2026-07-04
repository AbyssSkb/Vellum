import Foundation

struct MarkdownDocument: Equatable {
    let url: URL
    let source: String
    let sourceLineRanges: [NSRange]
    let outlineItems: [MarkdownOutlineItem]

    var lineCount: Int {
        sourceLineRanges.count
    }

    init(url: URL, source: String) {
        self.url = url
        self.source = source
        self.sourceLineRanges = MarkdownSourceLineIndexer.ranges(in: source)
        self.outlineItems = MarkdownOutlineBuilder.items(from: MarkdownSourceLineIndexer.headings(in: source))
    }
}

struct MarkdownHeading: Equatable {
    let id: String
    let title: String
    let level: Int
    let sourceLineIndex: Int
}

final class MarkdownOutlineItem: NSObject {
    let id: String
    let title: String
    let level: Int
    let sourceLineIndex: Int
    weak var parent: MarkdownOutlineItem?
    var children: [MarkdownOutlineItem] = []

    init(id: String, title: String, level: Int, sourceLineIndex: Int, parent: MarkdownOutlineItem?) {
        self.id = id
        self.title = title
        self.level = level
        self.sourceLineIndex = sourceLineIndex
        self.parent = parent
    }
}

enum MarkdownOutlineBuilder {
    static func items(from headings: [MarkdownHeading]) -> [MarkdownOutlineItem] {
        var roots: [MarkdownOutlineItem] = []
        var stack: [MarkdownOutlineItem] = []

        for heading in headings {
            while let last = stack.last, last.level >= heading.level {
                stack.removeLast()
            }

            let parent = stack.last
            let item = MarkdownOutlineItem(
                id: heading.id,
                title: heading.title,
                level: heading.level,
                sourceLineIndex: heading.sourceLineIndex,
                parent: parent
            )

            if let parent {
                parent.children.append(item)
            } else {
                roots.append(item)
            }
            stack.append(item)
        }

        return roots
    }
}

extension Array where Element == MarkdownOutlineItem {
    func flattened() -> [MarkdownOutlineItem] {
        flatMap { [$0] + $0.children.flattened() }
    }
}

enum MarkdownSourceLineIndexer {
    static func ranges(in source: String) -> [NSRange] {
        let nsString = source as NSString
        var ranges: [NSRange] = []
        var location = 0

        while location < nsString.length {
            let range = nsString.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = NSMaxRange(range)
        }

        if ranges.isEmpty || source.hasSuffix("\n") {
            ranges.append(NSRange(location: nsString.length, length: 0))
        }

        return ranges
    }

    static func headings(in source: String) -> [MarkdownHeading] {
        var headings: [MarkdownHeading] = []
        var fenceMarker: Character?
        var previousParagraph: (lineIndex: Int, text: String)?

        for (lineIndex, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            if let marker = fencedCodeMarker(in: rawLine) {
                if fenceMarker == marker {
                    fenceMarker = nil
                } else if fenceMarker == nil {
                    fenceMarker = marker
                }
                previousParagraph = nil
                continue
            }

            guard fenceMarker == nil else { continue }

            if let heading = atxHeading(in: rawLine, lineIndex: lineIndex) {
                headings.append(heading)
                previousParagraph = nil
                continue
            }

            if let paragraph = previousParagraph,
               let level = setextHeadingLevel(in: rawLine) {
                headings.append(
                    MarkdownHeading(
                        id: "\(paragraph.lineIndex)-\(level)-\(paragraph.text)",
                        title: paragraph.text,
                        level: level,
                        sourceLineIndex: paragraph.lineIndex
                    )
                )
                previousParagraph = nil
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            previousParagraph = trimmed.isEmpty || leadingSpaceCount(in: rawLine) > 3
                ? nil
                : (lineIndex, trimmed)
        }

        return headings
    }

    private static func atxHeading(in rawLine: String, lineIndex: Int) -> MarkdownHeading? {
        guard leadingSpaceCount(in: rawLine) <= 3 else { return nil }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let markerCount = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else { return nil }
        let afterMarkers = trimmed.dropFirst(markerCount)
        guard afterMarkers.isEmpty || afterMarkers.first?.isWhitespace == true else { return nil }

        let title = String(afterMarkers)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return MarkdownHeading(
            id: "\(lineIndex)-\(markerCount)-\(title)",
            title: title,
            level: markerCount,
            sourceLineIndex: lineIndex
        )
    }

    private static func setextHeadingLevel(in rawLine: String) -> Int? {
        guard leadingSpaceCount(in: rawLine) <= 3 else { return nil }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func fencedCodeMarker(in rawLine: String) -> Character? {
        guard leadingSpaceCount(in: rawLine) <= 3 else { return nil }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        return trimmed.prefix { $0 == marker }.count >= 3 ? marker : nil
    }

    private static func leadingSpaceCount(in line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}

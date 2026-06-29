import Foundation

public enum ReleaseNotesAtomParser {
    public static func releaseNotes(for tagName: String, from data: Data) -> String? {
        let parser = XMLParser(data: data)
        let delegate = ReleaseNotesAtomParserDelegate(tagName: tagName)
        parser.delegate = delegate
        let didParse = parser.parse()
        guard didParse || delegate.matchingContent != nil else { return nil }
        return markdownText(from: delegate.matchingContent)
    }

    private static func markdownText(from html: String?) -> String? {
        guard var text = html?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let replacements: [(String, String)] = [
            ("(?i)<h[1-6][^>]*>", "\n## "),
            ("(?i)</h[1-6]>", "\n"),
            ("(?i)<li[^>]*>", "\n- "),
            ("(?i)</li>", "\n"),
            ("(?i)<p[^>]*>", "\n"),
            ("(?i)</p>", "\n"),
            ("(?i)<br\\s*/?>", "\n")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeHTMLEntities(in: text)
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let markdown = lines.joined(separator: "\n")
        return markdown.nilIfEmpty
    }

    private static func decodeHTMLEntities(in text: String) -> String {
        var decoded = text
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, value) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        return decoded
    }
}

private final class ReleaseNotesAtomParserDelegate: NSObject, XMLParserDelegate {
    private let tagName: String
    private var isInsideEntry = false
    private var isInsideID = false
    private var isInsideContent = false
    private var currentID = ""
    private var currentContent = ""

    var matchingContent: String?

    init(tagName: String) {
        self.tagName = tagName
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "entry":
            isInsideEntry = true
            currentID = ""
            currentContent = ""
        case "id":
            isInsideID = isInsideEntry
        case "content":
            isInsideContent = isInsideEntry
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideID {
            currentID += string
        } else if isInsideContent {
            currentContent += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "id":
            isInsideID = false
        case "content":
            isInsideContent = false
        case "entry":
            if currentID.hasSuffix("/\(tagName)") {
                matchingContent = currentContent
                parser.abortParsing()
            }
            isInsideEntry = false
        default:
            break
        }
    }
}

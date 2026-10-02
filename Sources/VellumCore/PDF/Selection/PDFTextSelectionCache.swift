import PDFKit

@MainActor
final class PDFTextSelectionCache {
    private weak var document: PDFDocument?
    private var pageCount = 0
    private var starts: [Int]?
    private var pageTexts: [ObjectIdentifier: NSString] = [:]
    private var joinedText: NSString?
    private let lines = NSCache<NSNumber, CachedLines>()

    init() {
        lines.countLimit = 12
        lines.totalCostLimit = 8 * 1024 * 1024
    }

    func pageStarts(in document: PDFDocument) -> [Int] {
        prepare(document)
        if let starts { return starts }

        var result = [0]
        for index in 0..<document.pageCount {
            result.append(result.last! + (document.page(at: index)?.numberOfCharacters ?? 0))
        }
        starts = result
        return result
    }

    func text(on page: PDFPage, in document: PDFDocument) -> NSString? {
        prepare(document)
        let key = ObjectIdentifier(page)
        if let text = pageTexts[key] { return text }
        guard let text = page.string as NSString? else { return nil }
        pageTexts[key] = text
        return text
    }

    func text(in document: PDFDocument) -> NSString {
        prepare(document)
        if let joinedText { return joinedText }
        let result = (0..<document.pageCount).compactMap { index in
            document.page(at: index).flatMap { text(on: $0, in: document) as String? }
        }.joined() as NSString
        joinedText = result
        return result
    }

    func visualLines(
        on page: PDFPage,
        in document: PDFDocument,
        pageIndex: Int,
        pageStart: Int,
        box: PDFDisplayBox,
        build: () -> [VimTextLine]
    ) -> [VimTextLine] {
        prepare(document)
        let key = NSNumber(value: pageIndex)
        let characterCount = page.numberOfCharacters
        let bounds = page.bounds(for: box)
        if let cached = lines.object(forKey: key),
           cached.page === page,
           cached.pageStart == pageStart,
           cached.characterCount == characterCount,
           cached.rotation == page.rotation,
           cached.box == box,
           cached.bounds == bounds {
            return cached.value
        }
        let value = build()
        lines.setObject(CachedLines(
            page: page, pageStart: pageStart, characterCount: characterCount,
            box: box, bounds: bounds, value: value
        ), forKey: key, cost: value.reduce(0) { $0 + $1.characters.count * 64 })
        return value
    }

    private func prepare(_ document: PDFDocument) {
        guard self.document !== document || pageCount != document.pageCount else { return }
        self.document = document
        pageCount = document.pageCount
        starts = nil
        pageTexts.removeAll()
        joinedText = nil
        lines.removeAllObjects()
    }

    private final class CachedLines {
        weak var page: PDFPage?
        let pageStart: Int
        let characterCount: Int
        let rotation: Int
        let box: PDFDisplayBox
        let bounds: CGRect
        let value: [VimTextLine]

        init(page: PDFPage, pageStart: Int, characterCount: Int, box: PDFDisplayBox, bounds: CGRect, value: [VimTextLine]) {
            self.page = page
            self.pageStart = pageStart
            self.characterCount = characterCount
            rotation = page.rotation
            self.box = box
            self.bounds = bounds
            self.value = value
        }
    }
}

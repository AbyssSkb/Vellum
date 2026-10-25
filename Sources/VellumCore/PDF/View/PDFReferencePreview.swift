@preconcurrency import PDFKit

@MainActor
enum PDFReferencePreview {
    struct Region {
        let bounds: CGRect
        let title: AppText?
        var destination: PDFDestination? = nil
        var continuation: (page: PDFPage, bounds: CGRect)? = nil
        var additionalFragments: [(page: PDFPage, bounds: CGRect)] = []
    }

    enum Resolution {
        case region(Region)
        case pageContext
    }

    static func resolve(for annotation: PDFAnnotation, destination: PDFDestination) -> Resolution {
        guard let page = destination.page,
              !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .pageContext }
        if let number = PDFFigurePreview.number(for: annotation) {
            guard let preview = PDFFigurePreview.preview(number: number, destination: destination) else { return .pageContext }
            var region = Region(bounds: preview.bounds, title: .figurePreview(number))
            if let caption = preview.caption { region.continuation = (page, caption) }
            return .region(region)
        }
        let layout = Layout(page: page)
        guard !layout.lines.isEmpty else { return .pageContext }
        let point = PDFReferenceContent.normalizedPoint(destination.point, on: page)
        let target = target(for: annotation)
        if target == nil, let citation = citation(for: annotation) {
            let anchorMissing = [destination.point.x, destination.point.y].contains { !$0.isFinite || abs($0) >= 1e10 }
            guard var region = layout.bibliography(near: point, citation: citation, on: page, anchorMissing: anchorMissing) else { return .pageContext }
            if anchorMissing {
                region.destination = PDFDestination(page: page, at: CGPoint(x: region.bounds.minX, y: region.bounds.maxY))
            }
            return .region(region)
        }
        // Unclassified numbered objects should retain context instead of showing an unrelated paragraph.
        if target == nil, let selected = annotation.page?.selection(for: annotation.bounds)?.string,
           selected.trimmingCharacters(in: .whitespacesAndNewlines).range(of:
            #"(?i)^(?:(?:algorithms?|theorems?|footnotes?|算法|定理|脚注)\s*)?\d+[a-z]?(?:\s*(?:,|and|&|[-–—、及和])\s*\d+[a-z]?)*$"#,
            options: .regularExpression) != nil {
            return .pageContext
        }
        let bounds: CGRect?
        if let target {
            switch target.kind {
            case .table:
                guard let region = layout.tableRegion(number: target.number, near: point, on: page) else { return .pageContext }
                return .region(region)
            case .algorithm: bounds = layout.objects.object(kind: .algorithm, number: target.number, near: point)?.bounds
            case .equation: bounds = layout.equation(number: target.number, near: point)
            case .footnote: bounds = layout.footnote(number: target.number, near: point, on: page)
            case .section:
                if let region = layout.section(number: target.number, near: point, on: page) {
                    return .region(region)
                }
                if let document = page.document {
                    let nextIndex = document.index(for: page) + 1
                    if nextIndex < document.pageCount, let nextPage = document.page(at: nextIndex) {
                        let next = Layout(page: nextPage)
                        if var region = next.section(number: target.number, near: CGPoint(x: point.x, y: next.crop.maxY), on: nextPage) {
                            region.destination = PDFDestination(page: nextPage, at: CGPoint(x: region.bounds.minX, y: region.bounds.maxY))
                            return .region(region)
                        }
                    }
                }
                return .pageContext
            }
        } else {
            bounds = layout.paragraph(near: point)
        }
        if let bounds {
            return .region(Region(bounds: bounds.insetBy(dx: -2, dy: -2).intersection(layout.crop), title: target?.title))
        }
        return .pageContext
    }

    private static func citation(for annotation: PDFAnnotation) -> String? {
        guard let page = annotation.page, let string = page.string,
              let selection = page.selection(for: annotation.bounds) else { return nil }
        let text = string as NSString
        for index in 0..<selection.numberOfTextRanges(on: page) {
            let selected = selection.range(at: index, on: page)
            guard selected.location != NSNotFound, NSMaxRange(selected) <= text.length else { continue }
            let start = max(0, selected.location - 48)
            let context = NSRange(location: start, length: min(text.length, NSMaxRange(selected) + 48) - start)
            let pattern = #"\b(?:18|19|20)\d{2}[a-z]?\b|\[\s*\d+(?:\s*[,–-]\s*\d+)*\s*\]|\b\p{Lu}[\p{L}'’-]+(?:\s+et\s+al\.?)?\s*[,;(]?\s*(?:(?:18|19|20)\d{2}[a-z]?|[a-z](?=\s*[,;)])|n\.?\s*d\.?)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.matches(in: string, range: context).first(where: { NSIntersectionRange($0.range, selected).length > 0 }) {
                return text.substring(with: match.range)
            }
        }
        return namedDestination(for: annotation)?.hasPrefix("cite.") == true ? selection.string : nil
    }

    private static func namedDestination(for annotation: PDFAnnotation) -> String? {
        guard let page = annotation.page?.pageRef?.dictionary else { return nil }
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(page, "Annots", &annotations), let annotations else { return nil }
        for index in 0..<CGPDFArrayGetCount(annotations) {
            var raw: CGPDFDictionaryRef?, rect: CGPDFArrayRef?
            guard CGPDFArrayGetDictionary(annotations, index, &raw), let raw,
                  CGPDFDictionaryGetArray(raw, "Rect", &rect), let rect, CGPDFArrayGetCount(rect) == 4 else { continue }
            var coordinates = [CGPDFReal](repeating: 0, count: 4)
            guard (0..<4).allSatisfy({ CGPDFArrayGetNumber(rect, $0, &coordinates[$0]) }) else { continue }
            let bounds = CGRect(x: coordinates[0], y: coordinates[1], width: coordinates[2] - coordinates[0], height: coordinates[3] - coordinates[1]).standardized
            guard abs(bounds.minX - annotation.bounds.minX) < 0.5, abs(bounds.minY - annotation.bounds.minY) < 0.5,
                  abs(bounds.width - annotation.bounds.width) < 0.5, abs(bounds.height - annotation.bounds.height) < 0.5 else { continue }
            // PDFKit resolves named destinations to coordinates and drops the original target identity.
            var destination: CGPDFObjectRef?
            if !CGPDFDictionaryGetObject(raw, "Dest", &destination) {
                var action: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(raw, "A", &action), let action,
                      CGPDFDictionaryGetObject(action, "D", &destination) else { continue }
            }
            guard let destination else { continue }
            var string: CGPDFStringRef?, name: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(destination, .string, &string), let string { return CGPDFStringCopyTextString(string) as String? }
            if CGPDFObjectGetValue(destination, .name, &name), let name { return String(cString: name) }
        }
        return nil
    }

    private struct Target {
        enum Kind { case table, algorithm, equation, section, footnote }
        let kind: Kind
        let number: String
        var title: AppText? {
            switch kind {
            case .table: .tablePreview(number)
            case .algorithm: .algorithmPreview(number)
            case .equation: .equationPreview(number)
            case .section: .sectionPreview(number)
            case .footnote: nil
            }
        }
    }

    private static func target(for annotation: PDFAnnotation) -> Target? {
        var named: Target?
        if let name = namedDestination(for: annotation) {
            if name.hasPrefix("cite.") { return nil }
            let parts = name.split(separator: ".", maxSplits: 1)
            if parts.count == 2, ["hfootnote", "footnote"].contains(parts[0].lowercased()) {
                let selected = annotation.page?.selection(for: annotation.bounds)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Named footnote counters may differ from the printed marker.
                let number = selected.range(of: #"^\d+$|^[*†‡§¶]$"#, options: .regularExpression) != nil ? selected : ""
                return Target(kind: .footnote, number: number)
            }
            if parts.count == 2, ["table", "equation"].contains(parts[0].lowercased()),
               parts[1].range(of: #"^(?:[A-Z]\.?)?\d+(?:\.\d+)*[a-z]?$"#, options: .regularExpression) != nil {
                named = Target(kind: parts[0].lowercased() == "table" ? .table : .equation, number: String(parts[1]))
            }
            if parts.count == 2, parts[0].lowercased() == "algorithm",
               parts[1].range(of: #"^(?:[A-Z]\.?)?\d+(?:\.\d+)*[a-z]?$"#, options: .regularExpression) != nil {
                return Target(kind: .algorithm, number: String(parts[1]))
            }
            if parts.count == 2, ["section", "subsection", "subsubsection", "appendix"].contains(parts[0].lowercased()),
               parts[1].range(of: #"^(?:[A-Z]\.?)?\d+(?:\.\d+)*$|^[A-Z](?:\.\d+)*$"#, options: .regularExpression) != nil {
                return Target(kind: .section, number: String(parts[1]))
            }
        }
        guard let page = annotation.page, let string = page.string,
              let selection = page.selection(for: annotation.bounds) else { return named }
        let text = string as NSString
        let identifier = PDFReferenceTextLayout.objectNumberPattern
        let number = #"((?:"# + identifier + #")(?:\s*(?:,|and|&|[-–—、及和])\s*(?:"# + identifier + #"))*)"#
        let patterns: [(Target.Kind, String)] = [
            (.table, #"(?:\btables?|\btab\.?|表)\s*"# + number),
            (.algorithm, #"(?:\balgorithms?|\balg\.?|算法)\s*"# + number),
            (.equation, #"(?:\bequations?|\beqs?\.?|公式|式)\s*\(?\s*"# + number),
            (.equation, #"\(\s*((?:[A-Z]\.?)?\d+(?:\.\d+)*[a-z]?)\s*\)"#),
            (.footnote, #"(?:\bfootnotes?|脚注)\s*"# + number),
            (.section, #"(?:\bsec(?:-\s*)?tions?|\bsecs?\.?|\bappendix|章节|第)\s*"# + number)
        ]
        for index in 0..<selection.numberOfTextRanges(on: page) {
            let selected = selection.range(at: index, on: page)
            guard selected.location != NSNotFound, NSMaxRange(selected) <= text.length else { continue }
            let start = max(0, selected.location - 48)
            let context = NSRange(location: start, length: min(text.length, NSMaxRange(selected) + 24) - start)
            for (kind, pattern) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = regex.matches(in: string, range: context).first(where: {
                          NSIntersectionRange($0.range, selected).length > 0
                      }) else { continue }
                let numbers = (try? NSRegularExpression(pattern: identifier, options: .caseInsensitive))?.matches(in: string, range: match.range(at: 1)) ?? []
                let selectedNumber = numbers.first { NSIntersectionRange($0.range, selected).length > 0 } ?? numbers.first
                guard let selectedNumber else { continue }
                return Target(kind: kind, number: text.substring(with: selectedNumber.range))
            }
        }
        return named
    }

    private struct Row {
        var bounds: CGRect
        var text: String
        var parts: Int
        var fontSize: CGFloat
    }

    @MainActor
    // shortcut: Ambiguous unmarked reading flows need richer layout metadata.
    private struct Layout {
        let crop: CGRect
        let lines: [PDFReferenceTextLayout.Line]
        let rules: [CGRect]
        let objects: PDFReferenceObjectLayout
        let boldStarts: [CGPoint]

        init(page: PDFPage) {
            crop = page.bounds(for: .cropBox)
            lines = PDFReferenceTextLayout.lines(on: page)
            rules = page.pageRef.map(PDFGraphicBounds.layoutRules) ?? []
            boldStarts = page.pageRef.map(PDFReferenceTextStyle.boldLineStarts) ?? []
            objects = PDFReferenceObjectLayout(lines: lines, rules: rules, crop: crop)
        }

        func column(near anchor: CGRect) -> CGRect {
            let candidates = lines.filter {
                $0.bounds.width >= max(80, crop.width * 0.16)
                    && abs($0.bounds.midY - anchor.midY) < 120
                    && $0.bounds.minX <= anchor.midX + 12 && $0.bounds.maxX >= anchor.midX - 12
            }
            let aligned = candidates.filter { abs($0.bounds.minX - anchor.minX) <= max(12, anchor.height * 1.25) }
                .sorted { $0.bounds.midY > $1.bounds.midY }
            if let start = aligned.indices.min(by: { abs(aligned[$0].bounds.midY - anchor.midY) < abs(aligned[$1].bounds.midY - anchor.midY) }) {
                var first = start, last = start
                let gap = max(32, anchor.height * 2.5)
                while first > 0, aligned[first - 1].bounds.midY - aligned[first].bounds.midY < gap { first -= 1 }
                while last + 1 < aligned.count, aligned[last].bounds.midY - aligned[last + 1].bounds.midY < gap { last += 1 }
                let extent = union(aligned[first...last].map(\.bounds)).union(anchor)
                return CGRect(x: extent.minX, y: crop.minY, width: extent.width, height: crop.height)
            }
            let nearest = candidates.min {
                abs($0.bounds.midY - anchor.midY) + abs($0.bounds.midX - anchor.midX) * 0.1
                    < abs($1.bounds.midY - anchor.midY) + abs($1.bounds.midX - anchor.midX) * 0.1
            }?.bounds ?? anchor
            return CGRect(x: min(nearest.minX, anchor.minX), y: crop.minY,
                          width: max(nearest.maxX, anchor.maxX) - min(nearest.minX, anchor.minX), height: crop.height)
        }

        func rows(in column: CGRect, including additional: [CGRect] = []) -> [Row] {
            let selected = lines.filter { ($0.bounds.minX >= column.minX - 8 && $0.bounds.maxX <= column.maxX + 8) || additional.contains($0.bounds) }
            var result: [Row] = []
            for line in selected {
                if let last = result.indices.last,
                   abs(result[last].bounds.midY - line.bounds.midY) <= max(2, min(result[last].bounds.height, line.bounds.height) * 0.5) {
                    result[last].bounds = result[last].bounds.union(line.bounds)
                    result[last].text += " " + line.text
                    result[last].parts += 1
                    result[last].fontSize = max(result[last].fontSize, line.fontSize)
                } else {
                    result.append(Row(bounds: line.bounds, text: line.text, parts: 1, fontSize: line.fontSize))
                }
            }
            return result
        }

        func leading(in rows: [Row], near index: Int) -> CGFloat {
            let neighborhood = rows.filter { abs($0.bounds.midY - rows[index].bounds.midY) < 140 && $0.text.count > 20 }
            let steps = zip(neighborhood, neighborhood.dropFirst()).map { $0.bounds.midY - $1.bounds.midY }
                .filter { $0 >= 8 && $0 <= 20 }.sorted()
            return steps.isEmpty ? max(10, rows[index].bounds.height * 1.2) : steps[steps.count / 2]
        }

        func paragraphRange(from index: Int, in rows: [Row], backwards: Bool = false) -> ClosedRange<Int> {
            let step = leading(in: rows, near: index)
            var first = index, last = index
            if backwards {
                while first > 0 {
                    let previous = rows[first - 1], current = rows[first]
                    guard previous.bounds.midY - current.bounds.midY <= step * 1.4,
                          !isHeading(previous, after: first > 1 ? rows[first - 2] : nil, leading: step),
                          current.bounds.minX <= previous.bounds.minX + 3,
                          abs(previous.bounds.minX - current.bounds.minX) < step * 2 else { break }
                    first -= 1
                    if previous.bounds.minX > current.bounds.minX + 3 { break }
                }
            }
            while last + 1 < rows.count {
                let previous = rows[last], next = rows[last + 1]
                guard previous.bounds.midY - next.bounds.midY <= step * 1.4,
                      !isHeading(next, after: previous, leading: step),
                      abs(previous.bounds.minX - next.bounds.minX) < step * 2 else { break }
                if next.bounds.minX > previous.bounds.minX + 3 { break }
                last += 1
            }
            return first...last
        }

        func paragraph(near point: CGPoint) -> CGRect? {
            guard let seed = lines.min(by: { distance(point, $0.bounds) < distance(point, $1.bounds) }),
                  distance(point, seed.bounds) < 40 else { return nil }
            let rows = rows(in: column(near: seed.bounds))
            guard let index = rows.indices.min(by: { distance(point, rows[$0].bounds) < distance(point, rows[$1].bounds) }) else { return nil }
            let range = paragraphRange(from: index, in: rows, backwards: true)
            guard range.count > 1 else { return nil }
            return union(rows[range].map(\.bounds))
        }

        func bibliography(near point: CGPoint, citation: String, on page: PDFPage, anchorMissing: Bool = false) -> Region? {
            let marker = #"^\s*(?:\[\d+\]|\d+\.)(?:\s|(?=\p{L})|$)"#
            let numbered = lines.filter { $0.text.range(of: marker, options: .regularExpression) != nil }
            let hanging = lines.filter { first in
                lines.contains { next in
                    first.bounds.midY > next.bounds.midY && first.bounds.midY - next.bounds.midY <= max(24, first.bounds.height * 2)
                        && next.bounds.minX > first.bounds.minX + 4 && next.bounds.minX < first.bounds.minX + max(20, first.bounds.height * 2)
                }
            }
            let starts = numbered + lines.filter { line in
                hanging.contains { abs($0.bounds.minX - line.bounds.minX) <= 2 }
            }
            func anchorDistance(_ line: PDFReferenceTextLayout.Line) -> CGFloat {
                hypot(point.y - line.bounds.maxY, point.x - line.bounds.minX)
            }
            let nearest = starts.min(by: { anchorDistance($0) < anchorDistance($1) })
            if anchorMissing || nearest.map({ anchorDistance($0) >= 40 }) != false {
                let number = citation.range(of: #"^\s*\[?\s*(\d+)\s*\]?\s*$"#, options: .regularExpression)
                    .map { String(citation[$0]).filter(\.isNumber) }
                let author = citation.range(of: #"^\p{Lu}[\p{L}'’-]+"#, options: .regularExpression).map { String(citation[$0]) }
                let year = citation.range(of: #"\b(?:18|19|20)\d{2}[a-z]?\b"#, options: .regularExpression).map { String(citation[$0]) }
                guard number != nil || (author != nil && year != nil) else { return nil }
                let candidates = lines.filter { line in
                    starts.contains { $0.bounds == line.bounds }
                        && (number.map { line.text.range(of: #"^\s*(?:\["# + NSRegularExpression.escapedPattern(for: $0)
                            + #"\]|"# + NSRegularExpression.escapedPattern(for: $0) + #"\.)(?:\s|(?=\p{L})|$)"#,
                            options: .regularExpression) != nil }
                            ?? author.map { line.text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#,
                                options: .regularExpression) != nil } ?? false)
                }
                let matches = candidates.compactMap { candidate -> Region? in
                    guard let region = bibliography(near: CGPoint(x: candidate.bounds.minX, y: candidate.bounds.maxY),
                                                    citation: citation, on: page) else { return nil }
                    if let year {
                        var text = page.selection(for: region.bounds)?.string ?? ""
                        if let continuation = region.continuation {
                            text += " " + (continuation.page.selection(for: continuation.bounds)?.string ?? "")
                        }
                        guard text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: year) + #"\b"#,
                                         options: .regularExpression) != nil else { return nil }
                    }
                    return region
                }
                return matches.count == 1 ? matches[0] : nil
            }
            guard let seed = nearest else { return nil }
            let isNumbered = seed.text.range(of: marker, options: .regularExpression) != nil
            let extent = column(near: seed.bounds)
            let neighbor = lines.filter {
                $0.bounds.minX > max(extent.maxX + 12, seed.bounds.minX + max(80, crop.width * 0.16))
                    && $0.bounds.width > 80 && abs($0.bounds.midY - seed.bounds.midY) < 80
            }
            let right = (starts.filter {
                $0.bounds.minX > seed.bounds.minX + max(80, crop.width * 0.16)
            } + neighbor).map(\.bounds.minX).min() ?? crop.maxX
            // Justified first rows can be split into short fragments by the general text layout.
            var rows: [Row] = []
            for line in lines where line.bounds.minX >= seed.bounds.minX - 8 && line.bounds.minX < right - 8 {
                if let last = rows.indices.last,
                   abs(rows[last].bounds.midY - line.bounds.midY) <= max(2, min(rows[last].bounds.height, line.bounds.height) * 0.5) {
                    rows[last].bounds = rows[last].bounds.union(line.bounds)
                    rows[last].text += " " + line.text
                    rows[last].parts += 1
                    rows[last].fontSize = max(rows[last].fontSize, line.fontSize)
                } else {
                    rows.append(Row(bounds: line.bounds, text: line.text, parts: 1, fontSize: line.fontSize))
                }
            }
            guard let first = rows.firstIndex(where: { $0.bounds.intersects(seed.bounds) }) else { return nil }
            let step = leading(in: rows, near: first)
            var last = first
            while last + 1 < rows.count {
                let next = rows[last + 1]
                guard rows[last].bounds.midY - next.bounds.midY <= step * 1.7,
                      next.text.range(of: marker, options: .regularExpression) == nil || next.bounds.minX > seed.bounds.minX + 3,
                      !isHeading(next.text) || next.bounds.minX > seed.bounds.minX + 3,
                      isNumbered || next.bounds.minX > seed.bounds.minX + 3 else { break }
                last += 1
            }
            var text = rows[first...last].map(\.text).joined(separator: " ")
            let year = #"\b(?:18|19|20)\d{2}[a-z]?\b"#
            let expectedYear = citation.range(of: year, options: .regularExpression).map { String(citation[$0]) }
            let bounds = union(rows[first...last].map(\.bounds))
            guard !lines.contains(where: { $0.bounds.minX >= right - 8 && bounds.intersects($0.bounds) }) else { return nil }
            var region = Region(bounds: bounds.insetBy(dx: -2, dy: -2).intersection(crop), title: nil)
            let atPageEnd = bounds.minY < crop.minY + max(120, crop.height * 0.2)
                && rows.dropFirst(last + 1).allSatisfy {
                    $0.bounds.maxY < crop.minY + 80 && $0.text.range(of: #"^\s*\d+\s*$"#, options: .regularExpression) != nil
                }
            if atPageEnd, let document = page.document, let nextPage = document.page(at: document.index(for: page) + 1) {
                let next = Layout(page: nextPage)
                let column = CGRect(x: seed.bounds.minX, y: next.crop.minY, width: right - seed.bounds.minX - 8, height: next.crop.height)
                let continuationRows = next.rows(in: column)
                if let firstRow = continuationRows.first,
                   firstRow.bounds.minY > next.crop.maxY - max(120, next.crop.height * 0.2),
                   firstRow.bounds.minX > seed.bounds.minX + 3,
                   abs(firstRow.bounds.minX - rows[last].bounds.minX) <= max(4, seed.bounds.height * 0.65) {
                    let nextStep = next.leading(in: continuationRows, near: 0)
                    var end = 0
                    while end + 1 < continuationRows.count {
                        let row = continuationRows[end + 1]
                        guard continuationRows[end].bounds.midY - row.bounds.midY <= nextStep * 1.7,
                              row.bounds.minX > seed.bounds.minX + 3 else { break }
                        end += 1
                    }
                    let combined = text + " " + continuationRows[0...end].map(\.text).joined(separator: " ")
                    if let expectedYear {
                        guard combined.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: expectedYear) + #"\b"#,
                                             options: .regularExpression) != nil else { return nil }
                    }
                    let continuation = union(continuationRows[0...end].map(\.bounds))
                    guard !next.lines.contains(where: { $0.bounds.minX >= right - 8 && continuation.intersects($0.bounds) }) else { return nil }
                    region.continuation = (nextPage, continuation.insetBy(dx: -2, dy: -2).intersection(next.crop))
                    text = combined
                }
            }
            let hasYear = text.range(of: year, options: .regularExpression) != nil
            let undated = expectedYear == nil
            let author = citation.range(of: #"^\p{Lu}[\p{L}'’-]+"#, options: .regularExpression).map { String(citation[$0]) }
            let matchesAuthor = author.map { text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#, options: .regularExpression) != nil } ?? false
            guard hasYear || (undated && matchesAuthor) else { return nil }
            return region
        }

        func footnote(number: String, near point: CGPoint, on page: PDFPage) -> CGRect? {
            let marker = #"^\s*(\d+|[*†‡§¶])(?:[.)])?(?=\s|\p{L}|$)"#
            guard let pattern = try? NSRegularExpression(pattern: marker) else { return nil }
            func identity(_ text: String) -> String? {
                let text = text as NSString
                guard let match = pattern.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
                return text.substring(with: match.range(at: 1))
            }
            let candidates = lines.filter { line in
                identity(line.text).map { number.isEmpty || $0 == number } ?? false
            }
            guard let seed = candidates.min(by: { distance(point, $0.bounds) < distance(point, $1.bounds) }),
                  distance(point, seed.bounds) < 40 else { return nil }
            let separator = rules.filter {
                $0.width >= 40 && $0.height <= 2 && $0.minX <= seed.bounds.minX + 4
                    && $0.maxX >= seed.bounds.minX && $0.minY >= seed.bounds.maxY - 3
                    && $0.minY - seed.bounds.maxY < 160
            }.min { $0.minY < $1.minY }
            let above = lines.filter {
                $0.bounds.minY > seed.bounds.maxY && $0.fontSize > seed.fontSize * 1.02
                    && $0.bounds.width >= 80 && $0.bounds.maxX >= seed.bounds.minX
                    && $0.bounds.minX <= seed.bounds.maxX
            }.min { $0.bounds.minY < $1.bounds.minY }
            guard separator != nil || (above != nil && seed.bounds.maxY < crop.minY + crop.height * 0.4) else { return nil }
            let column = column(near: above?.bounds ?? seed.bounds)
            let extent = CGRect(x: min(column.minX, seed.bounds.minX) - 8, y: crop.minY,
                                width: max(column.maxX, seed.bounds.maxX) - min(column.minX, seed.bounds.minX) + 16,
                                height: crop.height)
            let rows = rows(in: extent).filter { $0.bounds.maxY <= (separator?.minY ?? seed.bounds.maxY) + 3 }
            guard let first = rows.firstIndex(where: { $0.bounds.intersects(seed.bounds) }) else { return nil }
            let step = leading(in: rows, near: first)
            var last = first
            while last + 1 < rows.count {
                let next = rows[last + 1]
                guard rows[last].bounds.midY - next.bounds.midY <= step * 1.7,
                      next.fontSize <= max(seed.fontSize * 1.15, seed.fontSize + 0.5),
                      !(identity(next.text) != nil && abs(next.bounds.minX - seed.bounds.minX) <= max(3, seed.bounds.height * 0.5)) else { break }
                last += 1
            }
            return union(rows[first...last].map(\.bounds))
        }

        func sectionColumn(near anchor: CGRect) -> CGRect {
            let local = column(near: anchor)
            let aligned = lines.filter {
                abs($0.bounds.minX - anchor.minX) <= max(3, anchor.height * 0.5)
                    && $0.bounds.height >= anchor.height * 0.7 && $0.bounds.height <= anchor.height * 1.3
            }
            let extent = union(aligned.map(\.bounds)).union(local)
            let neighbor = lines.filter {
                $0.bounds.minX > local.maxX + 8 && $0.bounds.width >= max(80, crop.width * 0.16)
                    && abs($0.bounds.midY - anchor.midY) < 120
            }.map(\.bounds.minX).min()
            let right = min(extent.maxX, neighbor.map { $0 - 8 } ?? crop.maxX)
            return CGRect(x: extent.minX, y: crop.minY, width: max(1, right - extent.minX), height: crop.height)
        }

        func flowColumn(after previous: CGRect? = nil, matching preceding: Row) -> CGRect? {
            let candidates = lines.filter { line in
                line.bounds.width >= max(60, crop.width * 0.1)
                    && line.bounds.minY > crop.minY + 48
                    && (previous.map { line.bounds.minX > $0.maxX + 8 } ?? true)
            }
            guard let left = candidates.map(\.bounds.minX).min() else { return nil }
            let aligned = candidates.filter { abs($0.bounds.minX - left) <= max(3, preceding.fontSize * 0.5) }
            guard let anchor = aligned.first else { return nil }
            return sectionColumn(near: anchor.bounds)
        }

        func flowRows(in column: CGRect) -> [Row] {
            flowBody(rows(in: column))
        }

        func flowBody(_ candidates: [Row]) -> [Row] {
            let captions = candidates.indices.filter {
                candidates[$0].text.range(of: #"(?i)^(?:figure|fig\.?|table|tab\.?|图|表)\s*\d+\s*[.|:：]"#,
                                          options: .regularExpression) != nil
            }.map { paragraphRange(from: $0, in: candidates) }
            return candidates.indices.filter { index in
                !captions.contains { $0.contains(index) }
                    && !(candidates[index].bounds.maxY < crop.minY + 80
                         && candidates[index].text.range(of: #"^\s*\d+\s*$"#, options: .regularExpression) != nil)
            }.map { candidates[$0] }
        }

        func endsColumn(_ rows: [Row], at index: Int) -> Bool {
            let last = rows[index]
            return last.bounds.minY < crop.minY + max(120, crop.height * 0.2)
                && rows.dropFirst(index + 1).allSatisfy {
                    $0.bounds.maxY < crop.minY + 120 && ($0.text.range(of: #"^\s*\d+\s*$"#, options: .regularExpression) != nil
                        || $0.bounds.height < last.bounds.height * 0.98)
                }
        }

        func emphasizedStart(_ bounds: CGRect) -> Bool {
            boldStarts.contains { abs($0.x - bounds.minX) <= 3 && bounds.insetBy(dx: -1, dy: -1).contains($0) }
        }

        func introducedRows(in column: CGRect, after preceding: Row, below top: CGFloat) -> [Row] {
            let heading = lines.first {
                $0.bounds.maxY <= top && $0.bounds.minX >= column.minX - 8 && $0.bounds.minX < column.midX && isHeading($0.text)
            }
            let emphasized = lines.filter {
                $0.bounds.maxY <= top && $0.bounds.minX > column.minX + 3 && $0.bounds.minX < column.midX
                    && $0.bounds.midY > (heading?.bounds.midY ?? crop.minY)
                    && abs($0.fontSize - preceding.fontSize) <= max(0.5, preceding.fontSize * 0.05)
                    && !isHeading($0.text) && emphasizedStart($0.bounds)
            }
            guard let first = emphasized.first else { return rows(in: column) }
            let additional = emphasized.filter { line in
                guard abs(line.bounds.minX - first.bounds.minX) <= 3 else { return false }
                return !lines.contains { neighbor in
                    neighbor.bounds.minX > column.midX && neighbor.bounds.minX < line.bounds.maxX + 8
                        && neighbor.bounds.width >= max(80, crop.width * 0.16)
                        && abs(neighbor.bounds.midY - line.bounds.midY) < 120
                }
            }
            return rows(in: column, including: additional.map(\.bounds))
        }

        func introducedList(from start: Int, in rows: [Row], left: CGFloat) -> Int? {
            guard start < rows.count else { return nil }
            if start > 0, rows[start - 1].bounds.minY - rows[start].bounds.maxY > max(36, rows[start - 1].bounds.height * 3) { return nil }
            let marker = #"^[•●▪◦‣–-]\s+"#
            func startsItem(_ row: Row) -> Bool {
                !isHeading(row.text) && (row.text.range(of: marker, options: .regularExpression) != nil
                    || (row.bounds.minX > left + 3 && emphasizedStart(row.bounds)))
            }
            guard startsItem(rows[start]) else { return nil }
            var end = paragraphRange(from: start, in: rows).upperBound
            while end + 1 < rows.count,
                  abs(rows[end + 1].bounds.minX - rows[start].bounds.minX) <= 3,
                  rows[end].bounds.minY - rows[end + 1].bounds.maxY <= max(24, rows[start].bounds.height * 2),
                  startsItem(rows[end + 1]) {
                end = paragraphRange(from: end + 1, in: rows).upperBound
            }
            return end
        }

        // shortcut: Compact columns need explicit style boundaries; unstyled or longer flows need richer layout metadata.
        func columnarList(after headings: CGRect, title: AppText?, on page: PDFPage) -> Region? {
            let body = rows(in: crop).filter { $0.bounds.maxY < headings.minY }
            guard body.count >= 3, body.prefix(3).allSatisfy({ $0.parts == 2 }),
                  let first = body.first, headings.minY - first.bounds.maxY <= 36 else { return nil }
            let starts = lines.filter { $0.bounds.intersects(first.bounds) }
            guard starts.count == 2, starts[1].bounds.minX - starts[0].bounds.minX > max(80, crop.width * 0.18),
                  emphasizedStart(starts[0].bounds), !emphasizedStart(starts[1].bounds) else { return nil }
            func entries(_ layout: Layout, x: CGFloat, below top: CGFloat, allowsLabel: Bool) -> (lines: [PDFReferenceTextLayout.Line], endsGroup: Bool) {
                let candidates = layout.lines.filter { abs($0.bounds.minX - x) <= 3 && $0.bounds.maxY <= top }
                var result: [PDFReferenceTextLayout.Line] = []
                for line in candidates {
                    if !(result.isEmpty && allowsLabel), layout.emphasizedStart(line.bounds) {
                        return (result, !layout.isHeading(line.text))
                    }
                    guard line.bounds.width < layout.crop.width * 0.35, line.text.count <= 60,
                          line.text.range(of: #"^[\p{L}\p{M}. &'’–-]+$"#, options: .regularExpression) != nil,
                          !line.text.hasSuffix("."),
                          abs(line.fontSize - starts[0].fontSize) <= max(0.5, starts[0].fontSize * 0.05),
                          result.last.map({ $0.bounds.midY - line.bounds.midY <= max(20, line.bounds.height * 1.5) }) ?? true else { break }
                    result.append(line)
                }
                return (result, false)
            }
            var columns: [[PDFReferenceTextLayout.Line]] = []
            for start in starts {
                let entry = entries(self, x: start.bounds.minX, below: headings.minY, allowsLabel: true)
                guard !entry.endsGroup else { return nil }
                columns.append(entry.lines)
            }
            guard columns.allSatisfy({ $0.count >= 3 }) else { return nil }
            var region = Region(bounds: headings.union(union(columns.flatMap { $0.map(\.bounds) })).insetBy(dx: -2, dy: -2).intersection(crop), title: title)
            if columns.allSatisfy({ $0.last!.bounds.minY < crop.minY + max(120, crop.height * 0.2) }),
               let document = page.document, let nextPage = document.page(at: document.index(for: page) + 1) {
                let following = Layout(page: nextPage)
                let continuation = entries(following, x: starts[0].bounds.minX, below: following.crop.maxY, allowsLabel: false)
                guard let first = continuation.lines.first, let last = continuation.lines.last,
                      first.bounds.minY > following.crop.maxY - max(120, following.crop.height * 0.2),
                      continuation.endsGroup || last.bounds.minY > following.crop.minY + max(120, following.crop.height * 0.2) else { return nil }
                region.continuation = (nextPage, union(continuation.lines.map(\.bounds)).insetBy(dx: -2, dy: -2).intersection(following.crop))
            }
            return region
        }

        func section(number: String, near point: CGPoint, on page: PDFPage) -> Region? {
            let pattern = #"^\s*(?:section\s+|appendix\s+|第)?"# + NSRegularExpression.escapedPattern(for: number) + #"(?![\dA-Za-z]|\.\d)(?:\s|[.:：]|节|章|$)"#
            guard let seed = matching(pattern, near: point) else { return nil }
            let column = sectionColumn(near: seed.bounds)
            var rows = rows(in: column)
            guard let index = rows.firstIndex(where: { $0.bounds.intersects(seed.bounds) }) else { return nil }
            var lastHeading = index
            let descendant = #"^\s*"# + NSRegularExpression.escapedPattern(for: number) + #"(?:\.\d+)+\.?\s+\p{L}"#
            while lastHeading + 1 < rows.count,
                  rows[lastHeading + 1].text.range(of: descendant, options: .regularExpression) != nil,
                  rows[lastHeading].bounds.minY - rows[lastHeading + 1].bounds.maxY <= max(36, rows[lastHeading].bounds.height * 3) {
                lastHeading += 1
            }
            let headings = union(rows[index...lastHeading].map(\.bounds))
            var region = Region(bounds: headings.insetBy(dx: -2, dy: -2).intersection(crop), title: .sectionPreview(number))
            if let list = columnarList(after: headings, title: region.title, on: page) { return list }
            let next = lastHeading + 1
            guard next < rows.count,
                  rows[lastHeading].bounds.minY - rows[next].bounds.maxY <= max(36, rows[lastHeading].bounds.height * 3) else { return region }
            if rows[next].text.range(of: #"(?i)^(?:table|tab\.?|表)\s*\d+\s*[.|:：]"#, options: .regularExpression) != nil,
               let caption = rows[next].text.range(of: #"\d+(?:\.\d+)*"#, options: .regularExpression),
               let bounds = table(number: String(rows[next].text[caption]), near: CGPoint(x: rows[next].bounds.minX, y: rows[next].bounds.maxY)) {
                return Region(bounds: headings.union(bounds).insetBy(dx: -2, dy: -2).intersection(crop), title: region.title)
            }
            guard !isHeading(rows[next].text) else { return region }
            let range = paragraphRange(from: next, in: rows)
            var lastIndex = range.upperBound
            if rows[lastIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":") {
                let introducer = rows[lastIndex]
                while lastIndex + 1 < rows.count,
                      rows[lastIndex + 1].bounds.minX > column.minX + 3,
                      rows[lastIndex].bounds.minY - rows[lastIndex + 1].bounds.maxY <= max(36, rows[lastIndex].bounds.height * 3),
                      !isHeading(rows[lastIndex + 1].text) {
                    lastIndex += 1
                }
                let legacyEnd = rows[lastIndex].bounds
                rows = introducedRows(in: column, after: introducer, below: introducer.bounds.minY)
                lastIndex = rows.firstIndex(where: { $0.bounds.intersects(legacyEnd) }) ?? lastIndex
                if let start = rows.firstIndex(where: { $0.bounds == introducer.bounds }),
                   let end = introducedList(from: start + 1, in: rows, left: column.minX) {
                    lastIndex = max(lastIndex, end)
                }
                if lastIndex > range.upperBound, lastIndex + 1 < rows.count,
                   rows[lastIndex + 1].text.range(of: #"(?i)^(?:where\b|here\b|其中|式中)"#, options: .regularExpression) != nil,
                   rows[lastIndex].bounds.minY - rows[lastIndex + 1].bounds.maxY <= max(36, rows[lastIndex].bounds.height * 3) {
                    lastIndex = paragraphRange(from: lastIndex + 1, in: rows).upperBound
                }
            }
            let bounds = headings.union(union(rows[range.lowerBound...lastIndex].map(\.bounds)))
            region = Region(bounds: bounds.insetBy(dx: -2, dy: -2).intersection(crop), title: region.title)
            var current = self, currentPage = page, currentColumn = column
            var currentRows = rows, end = lastIndex
            while current.endsColumn(currentRows, at: end) {
                let last = currentRows[end]
                let introducesBlock = last.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":")
                guard introducesBlock || last.bounds.minX <= currentColumn.minX + max(3, last.fontSize * 0.3),
                      introducesBlock || last.text.range(of: #"[.!?。！？:;][\p{Pe}\p{Pf}\"']*\s*$"#, options: .regularExpression) == nil else { break }
                let nextColumn: CGRect
                if let right = current.flowColumn(after: currentColumn, matching: last) {
                    nextColumn = right
                } else {
                    guard let document = currentPage.document,
                          let nextPage = document.page(at: document.index(for: currentPage) + 1) else { break }
                    currentPage = nextPage
                    current = Layout(page: nextPage)
                    guard let left = current.flowColumn(matching: last) else { break }
                    nextColumn = left
                }
                var body = current.flowRows(in: nextColumn)
                if introducesBlock {
                    body = current.flowBody(current.introducedRows(in: nextColumn, after: last, below: current.crop.maxY))
                } else {
                    // Floating graphics can precede the first paragraph in a reading column.
                    guard let start = body.firstIndex(where: {
                        $0.bounds.minX <= nextColumn.minX + max(12, last.fontSize * 2)
                            && ($0.fontSize <= 0 || last.fontSize <= 0 || $0.fontSize >= last.fontSize * 0.95)
                    }) else { break }
                    body = Array(body[start...])
                }
                guard let first = body.first,
                      !current.isHeading(first, after: last, leading: current.leading(in: body, near: 0)),
                      first.fontSize <= 0 || last.fontSize <= 0
                        || abs(first.fontSize - last.fontSize) <= max(1, last.fontSize * 0.2),
                      introducesBlock || first.bounds.minX <= nextColumn.minX + max(3, last.fontSize * 0.3) else { break }
                if !introducesBlock {
                    let edges = current.rules.filter {
                        $0.width <= 2 && $0.height >= first.bounds.height * 2
                            && $0.minY <= first.bounds.midY && $0.maxY >= first.bounds.midY
                    }
                    guard !edges.contains(where: { $0.maxX <= first.bounds.minX + 1 })
                        || !edges.contains(where: { $0.minX >= first.bounds.maxX - 1 }) else { break }
                }
                if introducesBlock {
                    guard let listEnd = current.introducedList(from: 0, in: body, left: nextColumn.minX) else { break }
                    end = listEnd
                } else {
                    end = current.paragraphRange(from: 0, in: body).upperBound
                    let final = body[end]
                    if final.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":") {
                        let expanded = current.flowBody(current.introducedRows(in: nextColumn, after: final, below: final.bounds.minY))
                        if let position = expanded.firstIndex(where: { $0.bounds == final.bounds }),
                           let listEnd = current.introducedList(from: position + 1, in: expanded, left: nextColumn.minX) {
                            body = Array(body[0...end]) + Array(expanded[(position + 1)...])
                            end += listEnd - position
                        }
                    }
                }
                let bounds = union(body[0...end].map(\.bounds)).insetBy(dx: -2, dy: -2).intersection(current.crop)
                if region.continuation == nil { region.continuation = (currentPage, bounds) }
                else { region.additionalFragments.append((currentPage, bounds)) }
                currentColumn = nextColumn
                currentRows = body
            }
            return region
        }

        func equation(number: String, near point: CGPoint) -> CGRect? {
            let escaped = NSRegularExpression.escapedPattern(for: number)
            let identifier = #"(?:[A-Z]\.?)?\d+(?:\.\d+)*[a-z]?"#
            let standalone = #"^\s*\("# + identifier + #"\)\s*[.,]?$"#
            let labels = lines.filter {
                $0.text.range(of: #"\("# + identifier + #"\)\s*[.,]?$"#, options: .regularExpression) != nil
                    && ($0.text.range(of: standalone + #"|[=∈≈≤≥∑∏∫×÷∗]"#, options: .regularExpression) != nil)
            }
            let exact = labels.filter { $0.text.range(of: #"\(\s*"# + escaped + #"\s*\)\s*[.,]?$"#, options: .regularExpression) != nil }
            if exact.isEmpty, number.last?.isNumber == true {
                let members = labels.compactMap { line -> (String, CGPoint)? in
                    guard let range = line.text.range(of: #"(?<=\()"# + escaped + #"[a-z](?=\)\s*[.,]?$)"#,
                                                      options: .regularExpression) else { return nil }
                    return (String(line.text[range]), CGPoint(x: line.bounds.midX, y: line.bounds.midY))
                }
                let bounds = members.compactMap { equation(number: $0.0, near: $0.1) }
                return !bounds.isEmpty && bounds.count == members.count ? union(bounds) : nil
            }
            guard let label = exact.min(by: { distance(point, $0.bounds) < distance(point, $1.bounds) }) else { return nil }
            var column = column(near: label.bounds)
            if column.width < 80 { column = crop }
            column.size.width = max(1, label.bounds.maxX - column.minX)
            let otherLabels = labels.filter { abs($0.bounds.midY - label.bounds.midY) < max(8, label.bounds.height) }
            if let previous = otherLabels.filter({ $0.bounds.maxX < label.bounds.minX }).max(by: { $0.bounds.maxX < $1.bounds.maxX }) {
                column.origin.x = max(column.minX, previous.bounds.maxX + 8)
                column.size.width = max(1, label.bounds.maxX - column.minX)
            }
            let verticalNeighbors = labels.filter { $0.bounds.maxX >= column.minX && $0.bounds.minX <= column.maxX }
            let above = verticalNeighbors.filter { $0.bounds.midY > label.bounds.midY + 2 }.map(\.bounds.minY).min()
            let below = verticalNeighbors.filter { $0.bounds.midY < label.bounds.midY - 2 }.map(\.bounds.maxY).max()
            let bottom = max(label.bounds.minY - max(8, label.bounds.height), below.map { ($0 + label.bounds.minY) / 2 } ?? crop.minY)
            let top = min(label.bounds.maxY + max(8, label.bounds.height), above.map { ($0 + label.bounds.maxY) / 2 } ?? crop.maxY)
            let band = CGRect(x: column.minX - 3, y: bottom, width: column.width + 6, height: max(1, top - bottom))
            let parts = lines.filter { $0.bounds.midY >= band.minY && $0.bounds.midY <= band.maxY
                && $0.bounds.minX >= column.minX - 3 && $0.bounds.maxX <= column.maxX + 3 }
            guard parts.count > 1 || label.text.trimmingCharacters(in: .whitespaces).count > number.count + 2 else { return nil }
            return union(parts.map(\.bounds))
        }

        func table(number: String, near point: CGPoint) -> CGRect? {
            objects.object(kind: .table, number: number, near: point)?.bounds
        }

        func tableRegion(number: String, near point: CGPoint, on page: PDFPage) -> Region? {
            guard let object = objects.object(kind: .table, number: number, near: point) else { return nil }
            var region = Region(bounds: object.bounds.insetBy(dx: -2, dy: -2).intersection(crop), title: .tablePreview(number))
            let ownedRules = object.parts.flatMap(\.ruleIndices).map { rules[$0] }
                .filter { $0.width >= 24 && $0.height <= 3 }
            guard let reference = ownedRules.max(by: { $0.width < $1.width }),
                  let document = page.document else { return region }
            let matching = ownedRules.filter { tableRule($0, matches: reference) }
            guard matching.count >= 2 else { return region }
            var frame = union(matching)
            // A small complete table at a page edge does not establish ownership of the next frame.
            guard frame.height >= crop.height * 0.5 else { return region }
            var previous = self
            var index = document.index(for: page)
            while frame.minY <= previous.crop.minY + previous.crop.height * 0.14, index + 1 < document.pageCount {
                guard let nextPage = document.page(at: index + 1) else { break }
                let next = Layout(page: nextPage)
                guard let fragment = next.tableContinuation(number: number, matching: reference, after: previous) else { break }
                if region.continuation == nil { region.continuation = (nextPage, fragment.bounds) }
                else { region.additionalFragments.append((nextPage, fragment.bounds)) }
                frame = fragment.frame
                previous = next
                index += 1
            }
            return region
        }

        private func tableRule(_ rule: CGRect, matches reference: CGRect) -> Bool {
            let tolerance = max(2, reference.width * 0.01)
            return rule.height <= 3 && abs(rule.minX - reference.minX) <= tolerance
                && abs(rule.maxX - reference.maxX) <= tolerance
        }

        private func tableContinuation(number: String, matching reference: CGRect, after previous: Layout) -> (bounds: CGRect, frame: CGRect)? {
            let aligned = rules.filter { tableRule($0, matches: reference) }.sorted { $0.midY > $1.midY }
            guard let top = aligned.first, aligned.count >= 2 else { return nil }
            let related = lines.filter { $0.bounds.minX >= reference.minX - 2 && $0.bounds.minX < reference.maxX }
            let before = related.filter { $0.bounds.minY > top.maxY }
            let label = #"(?i)^\s*(?:table|tab\.?|表)\s*"# + NSRegularExpression.escapedPattern(for: number)
                + #"(?![\p{L}\d]|\.\d)\s*[:|：.](?!\d)"#
            let repeated = before.first { $0.text.range(of: label, options: .regularExpression) != nil }
                .map { union(objects.caption(startingAt: $0.bounds, owner: union(aligned)).map(\.bounds)) } ?? .null
            // A repeated caption retains identity; repeated margin text is running chrome.
            guard before.allSatisfy({ line in
                repeated.contains(line.bounds) || line.bounds.minY > crop.maxY - crop.height * 0.12 && previous.lines.contains {
                    $0.text == line.text && abs($0.bounds.minX - line.bounds.minX) <= 2
                        && abs(($0.bounds.midY - previous.crop.maxY) - (line.bounds.midY - crop.maxY)) <= 2
                }
            }) else { return nil }
            let caption = related.filter { $0.bounds.midY < top.minY && tableCaption($0.text) }
                .map(\.bounds.maxY).max() ?? crop.minY
            let family = aligned.filter { $0.minY > caption }
            guard family.count >= 2 else { return nil }
            let frame = union(family)
            let body = related.filter { $0.bounds.midY >= frame.minY && $0.bounds.midY <= frame.maxY }
            guard body.count >= 2 else { return nil }
            let size = body.map(\.fontSize).max() ?? 0
            guard body.allSatisfy({ $0.bounds.maxX <= frame.maxX + max(2, size) }) else { return nil }
            let bounds = frame.union(union(body.map(\.bounds))).union(repeated).insetBy(dx: -2, dy: -2).intersection(crop)
            return (bounds, frame)
        }

        private func tableCaption(_ text: String) -> Bool {
            text.range(of: #"(?i)^\s*(?:figure|fig\.?|table|tab\.?|algorithm|图|表|算法)\s*"#
                       + PDFReferenceTextLayout.objectNumberPattern + #"\s*[:|：.](?!\d)"#,
                       options: .regularExpression) != nil
        }

        func matching(_ pattern: String, near point: CGPoint) -> PDFReferenceTextLayout.Line? {
            lines.filter { $0.text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
                .min { distance(point, $0.bounds) < distance(point, $1.bounds) }
        }

        func isHeading(_ text: String) -> Bool {
            text.range(of: #"^(?:\d+(?:\.\d+)*\.?|[A-Z](?:\.\d+)+\.?|[A-Z]\.)\s+\p{L}|^第\s*\d+\s*[章节]|^(?i:figure|fig\.?|table|tab\.?|图|表)\s*\d+\s*[.|:：]"#, options: .regularExpression) != nil
        }

        // shortcut: Ambiguous numeric starts need sentence-continuation evidence; standalone prose needs richer heading metadata.
        func isHeading(_ row: Row, after previous: Row?, leading step: CGFloat) -> Bool {
            guard isHeading(row.text) else { return false }
            guard let previous,
                  row.text.range(of: #"^\d+\s+\p{L}"#, options: .regularExpression) != nil,
                  previous.text.range(of: #"[,，\-‐‑–]\s*$"#, options: .regularExpression) != nil,
                  previous.fontSize > 0, row.fontSize > 0,
                  abs(previous.fontSize - row.fontSize) <= max(0.5, previous.fontSize * 0.05),
                  previous.bounds.midY - row.bounds.midY <= step * 1.15 else { return true }
            return false
        }
    }

    private static func distance(_ point: CGPoint, _ bounds: CGRect) -> CGFloat {
        hypot(max(bounds.minX - point.x, 0, point.x - bounds.maxX), max(bounds.minY - point.y, 0, point.y - bounds.maxY))
    }

    private static func union(_ bounds: [CGRect]) -> CGRect {
        bounds.reduce(CGRect.null) { $0.union($1) }
    }
}

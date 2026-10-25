@preconcurrency import PDFKit

@MainActor
struct PDFReferenceObjectLayout {
    enum Kind { case table, algorithm }

    struct Part {
        enum Role { case caption, body, note, rule }
        let role: Role
        let bounds: CGRect
        var lineIndices: [Int] = []
        var ruleIndices: [Int] = []
    }

    struct Object {
        let parts: [Part]
        var bounds: CGRect { parts.reduce(.null) { $0.union($1.bounds) } }
    }

    let lines: [PDFReferenceTextLayout.Line]
    let rules: [CGRect]
    let crop: CGRect

    func object(kind: Kind, number: String, near point: CGPoint) -> Object? {
        let label = kind == .table ? #"(?:table|tab\.?|表)"# : #"(?:algorithm|算法)"#
        let pattern = #"(?i)^\s*"# + label + #"\s*"# + NSRegularExpression.escapedPattern(for: number)
            + #"(?![\dA-Za-z]|\.\d)"#
        let matching = lines.indices.filter { matches(lines[$0].text, pattern) }
        let explicit = matching.filter { hasCaptionDelimiter(lines[$0].text) }
        let described = matching.filter { matches(lines[$0].text, pattern + #"\s*[:|：]"#) }
        let preferred = described.isEmpty ? explicit : described
        guard let seed = (preferred.isEmpty ? matching : preferred).min(by: {
            distance(point, lines[$0].bounds) < distance(point, lines[$1].bounds)
        }) else { return nil }
        let candidates = ruledObjects(kind: kind, seed: seed)
        let competitors = kind == .table ? lines.indices.filter {
            !matching.contains($0) && isCaption(lines[$0].text) && hasCaptionDelimiter(lines[$0].text)
                && matches(lines[$0].text, #"(?i)^\s*(?:table|tab\.?|表)\s*"#)
        }.map { ruledObjects(kind: kind, seed: $0) } : []
        // A uniquely owned frame cannot be borrowed by a closer neighboring caption.
        let available = candidates.filter { candidate in
            !competitors.contains { alternatives in
                !alternatives.isEmpty && alternatives.allSatisfy { sameFrame($0.frame, candidate.frame) }
            }
        }
        if let best = available.min(by: { $0.score < $1.score }) { return Object(parts: best.parts) }
        // shortcut: Algorithms without a shared frame remain page context until code-flow ownership is available.
        guard kind == .table else { return nil }
        return unruledTable(seed: seed)
    }

    private struct Candidate {
        let parts: [Part]
        let frame: CGRect
        let score: CGFloat
    }

    private func ruledObjects(kind: Kind, seed: Int) -> [Candidate] {
        var candidates: [Candidate] = []
        let boundaries = lines.indices.filter { isCaption(lines[$0].text) && hasCaptionDelimiter(lines[$0].text) }
        for family in ruleFamilies() {
            let ordered = family.sorted { rules[$0].midY > rules[$1].midY }
            var groups = [[ordered[0]]]
            for index in ordered.dropFirst() {
                let previous = groups[groups.count - 1].last!
                let frame = rules[previous].union(rules[index])
                let interior = rows(in: frame, excluding: [])
                let headerBand = frame.height <= max(24, font(of: interior.flatMap(\.indices)) * 3.5)
                    && interior.contains { $0.indices.count > 1 }
                let caption = lines[seed].bounds
                let content = union(interior.map(\.bounds))
                let size = font(of: interior.flatMap(\.indices))
                // Interior separators share the outer caption rather than needing a caption beside every cell.
                let enclosure = union(family.filter { rule in
                    !boundaries.contains { caption in
                        horizontallyRelated(lines[caption].bounds, frame)
                            && lines[caption].bounds.midY > min(rules[rule].midY, frame.midY)
                            && lines[caption].bounds.midY < max(rules[rule].midY, frame.midY)
                    }
                }.map { rules[$0] })
                let captionExtent = kind == .table ? union(self.caption(startingAt: caption, owner: enclosure).map(\.bounds)) : caption
                let insetTextCell = kind == .table && !interior.isEmpty
                    && (interior.count >= 2 || frame.height <= max(24, size * 3.5)) && !caption.intersects(frame)
                    && rectangleDistance(captionExtent, enclosure) <= max(40, font(of: [seed]) * 4)
                    && horizontallyRelated(captionExtent, frame)
                    && frame.maxY - content.maxY <= max(16, size * 1.5) + 1
                    && interior.allSatisfy { row in
                        let size = font(of: row.indices)
                        let inset = max(3, size * 0.4)
                        return row.bounds.minX >= frame.minX + inset && row.bounds.maxX <= frame.maxX - inset
                            && size <= font(of: [seed]) + 0.5
                    }
                let crossesCaption = boundaries.contains {
                    (kind == .table || $0 != seed) && horizontallyRelated(lines[$0].bounds, frame)
                        && lines[$0].bounds.midY > frame.minY && lines[$0].bounds.midY < frame.maxY
                }
                let connected = !crossesCaption && !interior.isEmpty && !interior.contains { row in
                    if row.indices.contains(where: { isCaption(lines[$0].text) && $0 != seed }) { return true }
                    if row.indices.contains(seed) { return kind == .table }
                    let step = kind == .algorithm && isAlgorithmStep(row, among: interior)
                    if isHeading(row.text), row.indices.count == 1, !step, !insetTextCell { return true }
                    guard isProse(row) else { return false }
                    return kind == .table ? !headerBand && !insetTextCell : !step && !isAlgorithmInput(row, among: interior)
                }
                if connected { groups[groups.count - 1].append(index) }
                else { groups.append([index]) }
            }
            for group in groups where group.count >= 2 {
                let frame = union(group.map { rules[$0] })
                let owned = rows(in: frame, excluding: [seed])
                let tabular = owned.filter { $0.indices.count > 1 }.count
                let code = kind == .algorithm ? owned.filter { isAlgorithmStep($0, among: owned)
                    || matches($0.text, #"[←⟵]|(?i:^\s*(?:require|ensure|input|output)\b)"#) }.count : 0
                guard kind == .table ? tabular >= 1 || owned.count >= 2 : code >= 2 else { continue }
                let captions = caption(startingAt: lines[seed].bounds, owner: frame)
                let captionBounds = union(captions.map(\.bounds))
                let gap = rectangleDistance(captionBounds, frame)
                guard gap <= max(40, font(of: [seed]) * 4), horizontallyRelated(captionBounds, frame) else { continue }
                var parts = captions + owned.map { part(.body, indices: $0.indices) }
                let containedRules = rules.indices.filter { rules[$0].height <= 3 && frame.insetBy(dx: -2, dy: -1).contains(rules[$0]) }
                parts += containedRules.map { Part(role: .rule, bounds: rules[$0], ruleIndices: [$0]) }
                if kind == .table {
                    parts += notes(below: frame, caption: captionBounds, excluding: Set(parts.flatMap(\.lineIndices)))
                }
                candidates.append(Candidate(parts: parts, frame: frame, score: gap - CGFloat(tabular) * 0.1))
            }
        }
        return candidates
    }

    private func sameFrame(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 2 && abs(first.maxX - second.maxX) <= 2
            && abs(first.minY - second.minY) <= 2 && abs(first.maxY - second.maxY) <= 2
    }

    private func hasCaptionDelimiter(_ text: String) -> Bool {
        matches(text, #"(?i)^\s*(?:figure|fig\.?|table|tab\.?|algorithm|图|表|算法)\s*"#
            + PDFReferenceTextLayout.objectNumberPattern + #"\s*[:|：.](?!\d)"#)
    }

    func caption(startingAt first: CGRect, owner: CGRect) -> [Part] {
        var firstIndices = lines.indices.filter {
            lines[$0].bounds.intersection(first).width >= min(first.width, lines[$0].bounds.width) * 0.7
                && abs(lines[$0].bounds.midY - first.midY) <= max(2, first.height * 0.5)
        }
        guard !firstIndices.isEmpty else { return [Part(role: .caption, bounds: first)] }
        let size = font(of: firstIndices)
        var firstBounds = union(firstIndices.map { lines[$0].bounds }).union(first)
        let needsDescription = firstIndices.allSatisfy { hasCaptionDelimiter(lines[$0].text) && !isCaption(lines[$0].text) }
        for index in lines.indices.sorted(by: { lines[$0].bounds.minX < lines[$1].bounds.minX })
            where needsDescription && !firstIndices.contains(index) {
            let bounds = lines[index].bounds
            guard abs(bounds.midY - first.midY) <= max(2, first.height * 0.5),
                  bounds.minX >= firstBounds.maxX - 1, bounds.minX - firstBounds.maxX <= max(12, size * 1.8),
                  !isCaption(lines[index].text) else { continue }
            firstIndices.append(index)
            firstBounds = firstBounds.union(bounds)
        }
        let envelope = owner.union(firstBounds)
        let tolerance = max(8, size, envelope.width * 0.1)
        var result = [Part(role: .caption, bounds: firstBounds, lineIndices: firstIndices)]
        var previous = firstBounds
        var leading: CGFloat?
        for row in rows(in: CGRect(x: envelope.minX - tolerance, y: crop.minY,
                                  width: envelope.width + tolerance * 2, height: crop.height), excluding: Set(firstIndices)) {
            guard row.bounds.midY < previous.minY else { continue }
            if row.bounds.intersects(owner) { break }
            let shortReference = matches(row.text, #"(?i)^\s*(?:figure|fig\.?|table|tab\.?|图|表)\s*[A-Z]?\d+(?:\.\d+)*[.)]?\s*$"#)
            let step = previous.midY - row.bounds.midY
            guard previous.minY - row.bounds.maxY <= size * 1.2,
                  step <= (leading.map { $0 * 1.4 } ?? max(size * 2, first.height * 1.5)),
                  !isCaption(row.text), !isHeading(row.text),
                  font(of: row.indices) <= size * 1.12,
                  font(of: row.indices) >= size * (shortReference ? 0.45 : 0.8),
                  horizontallyRelated(row.bounds, envelope) else { break }
            result.append(part(.caption, indices: row.indices))
            if leading == nil { leading = step }
            previous = row.bounds
        }
        return result
    }

    private struct Row {
        var indices: [Int]
        var bounds: CGRect
        var text: String
    }

    private func rows(in bounds: CGRect, excluding: Set<Int>) -> [Row] {
        let selected = lines.indices.filter {
            !excluding.contains($0) && lines[$0].bounds.midY >= bounds.minY && lines[$0].bounds.midY <= bounds.maxY
                && lines[$0].bounds.minX >= bounds.minX - 4 && lines[$0].bounds.maxX <= bounds.maxX + 4
        }.sorted {
            if abs(lines[$0].bounds.midY - lines[$1].bounds.midY) > 2 { return lines[$0].bounds.midY > lines[$1].bounds.midY }
            return lines[$0].bounds.minX < lines[$1].bounds.minX
        }
        var result: [Row] = []
        for index in selected {
            let line = lines[index]
            if let last = result.indices.last,
               abs(result[last].bounds.midY - line.bounds.midY) <= max(2, min(line.bounds.height, result[last].bounds.height) * 0.5) {
                result[last].indices.append(index)
                result[last].bounds = result[last].bounds.union(line.bounds)
                result[last].text += " " + line.text
            } else { result.append(Row(indices: [index], bounds: line.bounds, text: line.text)) }
        }
        return result
    }

    private func ruleFamilies() -> [[Int]] {
        let horizontal = rules.indices.filter { rules[$0].width >= 24 && rules[$0].height <= 3 }
            .sorted { rules[$0].width > rules[$1].width }
        var result: [[Int]] = []
        for index in horizontal {
            if let group = result.indices.first(where: {
                let reference = rules[result[$0][0]]
                let tolerance = max(2, reference.width * 0.02)
                return abs(reference.minX - rules[index].minX) <= tolerance
                    && abs(reference.maxX - rules[index].maxX) <= tolerance
            }) { result[group].append(index) }
            else { result.append([index]) }
        }
        return result
    }

    private func unruledTable(seed: Int) -> Object? {
        let anchor = lines[seed].bounds
        let siblings = lines.indices.filter { $0 != seed && isCaption(lines[$0].text)
            && abs(lines[$0].bounds.midY - anchor.midY) < 120 }
        let left = siblings.filter { lines[$0].bounds.maxX < anchor.minX }.map { lines[$0].bounds.maxX + 4 }.max() ?? crop.minX
        let right = siblings.filter { lines[$0].bounds.minX > anchor.maxX }.map { lines[$0].bounds.minX - 4 }.min() ?? crop.maxX
        let numbers = lines.indices.filter { lines[$0].bounds.minX >= left && lines[$0].bounds.maxX <= right
            && matches(lines[$0].text, #"^\s*[-+−]?\d[\d\s.,±+−%↑↓-]*\s*$"#) }
        let repeated = numbers.filter { first in numbers.filter {
            abs(lines[$0].bounds.minX - lines[first].bounds.minX) <= 8
        }.count >= 2 }
        guard repeated.count >= 2 else { return nil }
        let numberRows = rows(in: union(repeated.map { lines[$0].bounds }), excluding: Set(lines.indices).subtracting(repeated))
        var clusters: [[Row]] = []
        for row in numberRows {
            if let last = clusters.indices.last, let previous = clusters[last].last,
               previous.bounds.minY - row.bounds.maxY <= max(24, font(of: row.indices) * 2.4) {
                clusters[last].append(row)
            } else { clusters.append([row]) }
        }
        guard let cluster = clusters.filter({ $0.count >= 2 }).min(by: {
            rectangleDistance(anchor, union($0.map(\.bounds))) < rectangleDistance(anchor, union($1.map(\.bounds)))
        }) else { return nil }
        let cells = cluster.flatMap(\.indices)
        let labels = cells.compactMap { cell in lines.indices.filter {
            abs(lines[$0].bounds.midY - lines[cell].bounds.midY) <= max(3, lines[cell].bounds.height * 0.5)
                && lines[$0].bounds.minX >= left && lines[$0].bounds.maxX < lines[cell].bounds.minX
        }.max { lines[$0].bounds.maxX < lines[$1].bounds.maxX } }
        var extent = union((cells + labels).map { lines[$0].bounds })
        let headers = lines.indices.filter { index in
            let bounds = lines[index].bounds
            return bounds.minY >= extent.maxY - 2 && bounds.minY - extent.maxY <= font(of: [index]) * 3
                && bounds.minX >= left && bounds.maxX <= right && !isCaption(lines[index].text)
                && !isProse(Row(indices: [index], bounds: bounds, text: lines[index].text))
                && (cells + labels).contains { cell in
                    let reference = lines[cell].bounds
                    let tolerance = max(4, font(of: [index]) * 0.6)
                    return abs(bounds.minX - reference.minX) <= tolerance || abs(bounds.midX - reference.midX) <= tolerance
                }
        }
        extent = extent.union(union(headers.map { lines[$0].bounds }))
        let captions = caption(startingAt: anchor, owner: extent)
        let captionBounds = union(captions.map(\.bounds))
        let excluded = Set(captions.flatMap(\.lineIndices))
        let column = CGRect(x: extent.minX - 4, y: crop.minY, width: extent.width + 8, height: crop.height)
        let selected = rows(in: column, excluding: excluded)
        var best: [Row] = []
        for above in [true, false] {
            let outward = selected.filter { above ? $0.bounds.midY > captionBounds.maxY : $0.bounds.midY < captionBounds.minY }
                .sorted { above ? $0.bounds.midY < $1.bounds.midY : $0.bounds.midY > $1.bounds.midY }
            var owned: [Row] = []
            var previous = captionBounds
            for row in outward {
                let gap = rectangleDistance(previous, row.bounds)
                guard gap <= (owned.isEmpty ? max(48, font(of: [seed]) * 4) : max(20, font(of: row.indices) * 1.8)),
                      !isCaption(row.text), !isProse(row), !isHeading(row.text) || row.indices.count > 1 else { break }
                if !above, !owned.isEmpty, matches(row.text, #"(?i)^\s*(?:notes?\b|注(?:释)?|[*†‡])"#) { break }
                owned.append(row)
                previous = row.bounds
            }
            if owned.filter({ $0.indices.count > 1 }).count >= 2, owned.count > best.count { best = owned }
        }
        guard !best.isEmpty else { return nil }
        let frame = union(best.map(\.bounds))
        var parts = captions + best.map { part(.body, indices: $0.indices) }
        parts += notes(below: frame, caption: captionBounds, excluding: Set(parts.flatMap(\.lineIndices)))
        return Object(parts: parts)
    }

    private func notes(below frame: CGRect, caption: CGRect, excluding: Set<Int>) -> [Part] {
        let envelope = frame.union(caption)
        let selected = rows(in: CGRect(x: envelope.minX - 4, y: crop.minY,
                                       width: envelope.width + 8, height: crop.height), excluding: excluding)
            .filter { $0.bounds.midY < min(frame.minY, caption.minY) }
        guard let first = selected.first else { return [] }
        let size = font(of: first.indices)
        let captionSize = lines.indices.filter { lines[$0].bounds.intersects(caption) }.map { font(of: [$0]) }.max() ?? size
        let explicit = matches(first.text, #"(?i)^\s*(?:notes?\b|注(?:释)?|[*†‡])"#)
        // shortcut: Same-size, unlabelled prose needs stronger semantic evidence before it can safely become a note.
        guard size < captionSize * 0.94 || explicit,
              min(frame.minY, caption.minY) - first.bounds.maxY <= max(16, size * 1.5),
              abs(first.bounds.minX - frame.minX) <= max(6, size), !isHeading(first.text), !isCaption(first.text) else { return [] }
        var result: [Part] = []
        var previous = first.bounds
        var leading: CGFloat?
        for row in selected {
            guard previous.minY - row.bounds.maxY <= size * 1.3,
                  leading.map({ previous.midY - row.bounds.midY <= $0 * 1.4 }) ?? true,
                  abs(font(of: row.indices) - size) <= max(0.5, size * 0.08),
                  abs(row.bounds.minX - first.bounds.minX) <= max(6, size * 1.5),
                  !isHeading(row.text), !isCaption(row.text) else { break }
            if result.count == 1 { leading = previous.midY - row.bounds.midY }
            result.append(part(.note, indices: row.indices))
            previous = row.bounds
        }
        return result
    }

    private func part(_ role: Part.Role, indices: [Int]) -> Part {
        Part(role: role, bounds: union(indices.map { lines[$0].bounds }), lineIndices: indices)
    }

    private func font(of indices: [Int]) -> CGFloat {
        let sizes = indices.map { lines[$0].fontSize > 0 ? lines[$0].fontSize : lines[$0].bounds.height }.sorted()
        return sizes.isEmpty ? 10 : sizes[sizes.count / 2]
    }

    private func isProse(_ row: Row) -> Bool {
        let words = row.text.split(whereSeparator: \.isWhitespace)
        let values = words.filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }.count
        return row.indices.count == 1 && words.count > 9 && values * 3 < words.count
    }

    private func stepNumber(_ row: Row) -> Int? {
        guard let range = row.text.range(of: #"^\s*\d+(?=[:：]|\.\s+|\s+\S)"#, options: .regularExpression) else { return nil }
        return Int(row.text[range].trimmingCharacters(in: .whitespaces))
    }

    private func isAlgorithmStep(_ row: Row, among rows: [Row]) -> Bool {
        guard let number = stepNumber(row) else { return false }
        let size = font(of: row.indices)
        return rows.contains { other in
            guard let neighbor = stepNumber(other), abs(neighbor - number) == 1 else { return false }
            return abs(font(of: other.indices) - size) <= max(1, size * 0.15)
                && abs(other.bounds.minX - row.bounds.minX) <= max(6, size * 1.5)
                && abs(other.bounds.midY - row.bounds.midY) <= max(36, size * 4)
        }
    }

    private func isAlgorithmInput(_ row: Row, among rows: [Row]) -> Bool {
        guard let index = rows.firstIndex(where: { $0.indices == row.indices }),
              let start = rows.prefix(index + 1).lastIndex(where: {
                  matches($0.text, #"(?i)^\s*(?:require|ensure|input|output)\b"#)
              }) else { return false }
        return !rows[start...index].contains { stepNumber($0) != nil }
            && abs(font(of: row.indices) - font(of: rows[start].indices)) <= max(1, font(of: row.indices) * 0.2)
    }

    private func isCaption(_ text: String) -> Bool {
        matches(text, #"(?i)^\s*(?:figure|fig\.?|table|tab\.?|algorithm|图|表|算法)\s*"#
            + PDFReferenceTextLayout.objectNumberPattern + #"(?:\s*[:|：.]\s*|\s+)\S"#)
    }

    private func isHeading(_ text: String) -> Bool {
        matches(text, #"^\s*(?:\d+(?:\.\d+)*\.?|[A-Z](?:\.\d+)+\.?)\s+\p{L}|^第\s*\d+\s*[章节]"#)
    }

    private func horizontallyRelated(_ first: CGRect, _ second: CGRect) -> Bool {
        min(first.maxX, second.maxX) - max(first.minX, second.minX) >= min(first.width, second.width) * 0.5
    }

    private func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private func union(_ bounds: [CGRect]) -> CGRect { bounds.reduce(.null) { $0.union($1) } }

    private func rectangleDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        hypot(max(first.minX - second.maxX, second.minX - first.maxX, 0),
              max(first.minY - second.maxY, second.minY - first.maxY, 0))
    }

    private func distance(_ point: CGPoint, _ bounds: CGRect) -> CGFloat {
        hypot(max(bounds.minX - point.x, point.x - bounds.maxX, 0), max(bounds.minY - point.y, point.y - bounds.maxY, 0))
    }
}

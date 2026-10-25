@preconcurrency import PDFKit

@MainActor
enum PDFReferenceTextLayout {
    static let objectNumberPattern = #"(?:(?:[A-Z]\.?)?\d+(?:\.\d+)*[a-z]?|[A-Z](?:\.\d+)*)(?![A-Za-z\p{N}])"#

    struct Line {
        let bounds: CGRect
        let text: String
        var fontSize: CGFloat = 0
    }

    static func lines(on page: PDFPage) -> [Line] {
        guard let text = page.string else { return [] }
        let source = text as NSString
        let attributed = page.attributedString
        let crop = page.bounds(for: .cropBox)
        var glyphs: [(range: NSRange, bounds: CGRect, alignment: CGRect, line: Int, fontSize: CGFloat)] = []
        var nativeOffset = 0
        var logicalLine = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byComposedCharacterSequences) { value, range, _, _ in
            guard let value else { return }
            if value.rangeOfCharacter(from: .newlines) != nil {
                logicalLine += 1
                return
            }
            let range = NSRange(range, in: text)
            let native = nativeOffset < page.numberOfCharacters ? page.characterBounds(at: nativeOffset) : CGRect.null
            nativeOffset += range.length
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            // Repair a taller neighbor's inherited line box only when native glyph geometry agrees with the selection.
            let selection = page.selection(for: range)?.bounds(for: page) ?? native
            let bounds = native.width > 0 && native.height > 0 && selection.height > native.height * 1.5
                && selection.insetBy(dx: -0.5, dy: -0.5).contains(native)
                && abs(native.minX - selection.minX) <= 1 && abs(native.maxX - selection.maxX) <= 1 ? native : selection
            guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0, bounds.intersects(crop) else { return }
            let font = attributed.flatMap { range.location < $0.length
                ? $0.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont : nil }
            glyphs.append((range, bounds.intersection(crop), selection, logicalLine, font?.pointSize ?? 0))
        }

        let rows = Dictionary(grouping: glyphs.indices, by: { glyphs[$0].line }).values.flatMap { logical -> [[Int]] in
            let sorted = logical.sorted {
                let lhs = glyphs[$0].alignment
                let rhs = glyphs[$1].alignment
                if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
                if lhs.midX != rhs.midX { return lhs.midX < rhs.midX }
                return glyphs[$0].range.location < glyphs[$1].range.location
            }
            var physical: [[Int]] = []
            for index in sorted {
                let bounds = glyphs[index].alignment
                if let last = physical.indices.last, let anchor = physical[last].first {
                    let reference = glyphs[anchor].alignment
                    if abs(reference.midY - bounds.midY) <= max(2, min(reference.height, bounds.height) * 0.55) {
                        physical[last].append(index)
                        continue
                    }
                }
                physical.append([index])
            }
            return physical
        }

        return rows.flatMap { row in
            let characters = row.map { index in
                let bounds = glyphs[index].bounds
                return VimTextLineCharacter(globalOffset: index, minX: bounds.minX, centerX: bounds.midX,
                                            maxX: bounds.maxX, centerY: bounds.midY, height: bounds.height)
            }.sorted {
                if $0.centerX != $1.centerX { return $0.centerX < $1.centerX }
                return glyphs[$0.globalOffset].range.location < glyphs[$1.globalOffset].range.location
            }
            let heights = characters.map(\.height).sorted()
            let gap = max(12, heights[heights.count / 2] * 1.8)
            return VisualLineGeometry.splitVisualLineSegments(characters, gapThreshold: gap).map { segment in
                var bounds = CGRect.null
                var result = ""
                var previous: (range: NSRange, bounds: CGRect)?
                for character in segment {
                    let glyph = glyphs[character.globalOffset]
                    if let previous, glyph.range.location > NSMaxRange(previous.range) {
                        let gap = NSRange(location: NSMaxRange(previous.range), length: glyph.range.location - NSMaxRange(previous.range))
                        if glyph.bounds.minX - previous.bounds.maxX > 0.5,
                           source.substring(with: gap).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            result += " "
                        }
                    }
                    result += source.substring(with: glyph.range)
                    bounds = bounds.union(glyph.bounds)
                    previous = (glyph.range, glyph.bounds)
                }
                let sizes = segment.map { glyphs[$0.globalOffset].fontSize }.filter { $0 > 0 }.sorted()
                return Line(bounds: bounds, text: result, fontSize: sizes.isEmpty ? 0 : sizes[sizes.count / 2])
            }
        }.sorted {
            let lhsRow = ($0.bounds.midY / 2).rounded()
            let rhsRow = ($1.bounds.midY / 2).rounded()
            if lhsRow != rhsRow { return lhsRow > rhsRow }
            return $0.bounds.minX < $1.bounds.minX
        }
    }
}

@preconcurrency import PDFKit

@MainActor
enum PDFFigurePreview {
    static func number(for annotation: PDFAnnotation) -> String? {
        let identifier = #"[A-Z]?\d+(?:\.\d+)*(?:\s*\([a-z]\))?"#
        guard let page = annotation.page, let text = page.string as NSString?,
              let selection = page.selection(for: annotation.bounds),
              let pattern = try? NSRegularExpression(pattern: #"(?i)(?:\bfig(?:[-‐‑\x{00AD}]?\s*ure)?s?\.?|图)\s*("#
                + identifier + #")(?:\s*(?:,|and|&|[-–—、及和])\s*"# + identifier + #")*"#),
              let numbers = try? NSRegularExpression(pattern: "(?i)" + identifier) else { return nil }
        for index in 0..<selection.numberOfTextRanges(on: page) {
            let range = selection.range(at: index, on: page)
            guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { continue }
            let start = max(0, range.location - 40)
            let context = NSRange(location: start, length: min(text.length, NSMaxRange(range) + 24) - start)
            if let match = pattern.matches(in: text as String, range: context).first(where: {
                NSIntersectionRange($0.range, range).length > 0
            }) {
                let number = numbers.matches(in: text as String, range: match.range).first {
                    NSIntersectionRange($0.range, range).length > 0
                }?.range ?? match.range(at: 1)
                return text.substring(with: number).replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            }
        }
        return nil
    }

    static func crop(number: String, destination: PDFDestination) -> CGRect? {
        guard let figure = figureCrop(number: number, destination: destination), let page = destination.page else { return nil }
        return figure.graphic.union(figure.caption).insetBy(dx: -2, dy: -2).intersection(page.bounds(for: .cropBox))
    }

    static func preview(number: String, destination: PDFDestination) -> (bounds: CGRect, caption: CGRect?)? {
        let suffix = number.range(of: #"\([a-z]\)$"#, options: [.regularExpression, .caseInsensitive])
        let parent = suffix.map { String(number[..<$0.lowerBound]) } ?? number
        guard let figure = figureCrop(number: parent, destination: destination), let page = destination.page,
              let pageRef = page.pageRef else { return nil }
        let crop = page.bounds(for: .cropBox)
        let whole = figure.graphic.union(figure.caption).insetBy(dx: -2, dy: -2).intersection(crop)
        guard let suffix else { return (whole, nil) }
        let requested = String(number[suffix]).lowercased()
        let lines = PDFReferenceTextLayout.lines(on: page)
        let labels = lines.filter {
            whole.contains($0.bounds) && $0.bounds.minY > figure.caption.maxY
                && $0.text.range(of: #"^\([a-z]\)$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let identities = labels.map { $0.text.lowercased() }
        // shortcut: Shared graphic streams and mixed inline captions retain the whole figure until ownership is known.
        guard labels.count >= 2, Set(identities).count == labels.count,
              let selected = identities.firstIndex(of: requested) else { return (whole, nil) }
        let graphicRegions = PDFGraphicBounds.regions(on: pageRef)
        let graphics = graphicRegions.filter {
            $0.width >= 24 && $0.height >= 24 && figure.graphic.insetBy(dx: -2, dy: -2).contains($0)
        }
        func belongs(_ graphic: CGRect, to label: PDFReferenceTextLayout.Line) -> Bool {
            let gap = graphic.minY - label.bounds.maxY
            return label.bounds.midX >= graphic.minX && label.bounds.midX <= graphic.maxX
                && gap >= -2 && gap <= max(36, label.bounds.height * 4)
        }
        let panels = labels.indices.compactMap { index in
            graphics.filter { graphic in
                belongs(graphic, to: labels[index]) && !labels.indices.contains { other in
                    other != index && (belongs(graphic, to: labels[other]) || graphic.intersects(labels[other].bounds))
                }
            }.max { $0.width * $0.height < $1.width * $1.height }
        }
        guard panels.count == labels.count else { return (whole, nil) }
        for first in panels.indices {
            for second in panels.indices where second > first {
                guard !panels[first].intersects(panels[second]) else { return (whole, nil) }
            }
        }
        let owned = (panels + labels.map(\.bounds) + figure.parts.map(\.bounds)).map { $0.insetBy(dx: -2, dy: -2) }
        // Unassigned text or small graphics may be a shared legend; keep the complete figure when ownership is unclear.
        guard !lines.contains(where: { line in
            whole.intersects(line.bounds) && !owned.contains(where: { $0.contains(line.bounds) })
        }), !graphicRegions.contains(where: { graphic in
            whole.intersects(graphic) && !owned.contains(where: { $0.contains(graphic) })
                && !panels.allSatisfy({ graphic.insetBy(dx: -2, dy: -2).contains($0) })
        }) else { return (whole, nil) }
        let marker = #"(?i)^(?:(?:figure|fig\.?|图)\s*"# + NSRegularExpression.escapedPattern(for: parent)
            + #"[^\p{L}\d]*?)?(\([a-z]\))\s*\p{L}"#
        guard let pattern = try? NSRegularExpression(pattern: marker),
              let allMarkers = try? NSRegularExpression(pattern: #"(?i)\([a-z]\)"#) else { return (whole, nil) }
        var starts: [(identity: String, index: Int)] = []
        for (index, part) in figure.parts.enumerated() {
            let text = part.lineIndices.map { lines[$0].text }.joined(separator: " ") as NSString
            let range = NSRange(location: 0, length: text.length)
            guard allMarkers.numberOfMatches(in: text as String, range: range) <= 1 else { return (whole, nil) }
            if let match = pattern.firstMatch(in: text as String, range: range) {
                starts.append((text.substring(with: match.range(at: 1)).lowercased(), index))
            }
        }
        guard starts.first?.index == 0, starts.count == labels.count,
              Set(starts.map(\.identity)) == Set(identities),
              let captionIndex = starts.firstIndex(where: { $0.identity == requested }) else { return (whole, nil) }
        let end = captionIndex + 1 < starts.count ? starts[captionIndex + 1].index : figure.parts.count
        let caption = figure.parts[starts[captionIndex].index..<end].reduce(CGRect.null) { $0.union($1.bounds) }
        let body = panels[selected].union(labels[selected].bounds).insetBy(dx: -2, dy: -2).intersection(crop)
        guard !panels.indices.contains(where: { $0 != selected && body.intersects(panels[$0]) }),
              !labels.indices.contains(where: { $0 != selected && body.intersects(labels[$0].bounds) }) else { return (whole, nil) }
        return (body, caption.insetBy(dx: -2, dy: -2).intersection(crop))
    }

    private static func figureCrop(number: String, destination: PDFDestination)
        -> (graphic: CGRect, caption: CGRect, parts: [PDFReferenceObjectLayout.Part])? {
        guard let page = destination.page, let pageRef = page.pageRef,
              let text = page.string as NSString?,
              let pattern = try? NSRegularExpression(pattern:
                #"(?i)(?:\bfigure|\bfig\.?|图)\s*"#
                + NSRegularExpression.escapedPattern(for: number) + #"(?![\dA-Za-z]|\.\d)"#) else { return nil }
        let point = destination.point
        let graphics = PDFGraphicBounds.regions(on: pageRef)
        let lines = PDFReferenceTextLayout.lines(on: page)
        var candidates: [(graphic: CGRect, caption: CGRect, score: CGFloat)] = []
        for match in pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let logicalRange = text.lineRange(for: match.range)
            let firstRange = NSRange(location: match.range.location, length: NSMaxRange(logicalRange) - match.range.location)
            guard let firstBounds = lineSegment(in: firstRange, text: text, page: page) else { continue }
            guard firstBounds.width > 0, firstBounds.height > 0 else { continue }
            // An inline body reference cannot own the graphic's caption.
            guard lines.contains(where: { line in
                let value = line.text.trimmingCharacters(in: .whitespaces)
                return abs(line.bounds.minX - firstBounds.minX) <= 2
                    && abs(line.bounds.midY - firstBounds.midY) <= max(2, firstBounds.height * 0.5)
                    && pattern.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length))?.range.location == 0
            }) else { continue }
            let panels = graphics.filter { graphic in
                let gap = graphic.minY - firstBounds.maxY
                let overlap = max(0, min(graphic.maxX, firstBounds.maxX) - max(graphic.minX, firstBounds.minX))
                return graphic.width >= 24 && graphic.height >= 24
                    && gap >= 0 && gap <= max(36, firstBounds.height * 4)
                    && overlap >= min(graphic.width, firstBounds.width) * 0.5
            }
            let graphic = panels.reduce(CGRect.null) { $0.union($1) }
            let overlap = min(graphic.maxX, firstBounds.maxX) - max(graphic.minX, firstBounds.minX)
            guard !graphic.isNull, graphic.width >= max(24, firstBounds.width * 0.55),
                  overlap >= min(graphic.width, firstBounds.width) * 0.75 else { continue }
            let target = graphic.union(firstBounds)
            let distance = hypot(max(target.minX - point.x, 0, point.x - target.maxX),
                                 max(target.minY - point.y, 0, point.y - target.maxY))
            guard distance <= 40 else { continue }
            candidates.append((graphic, firstBounds, distance + abs(graphic.minY - firstBounds.maxY)))
        }
        guard let best = candidates.min(by: { $0.score < $1.score }) else { return nil }
        let layout = PDFReferenceObjectLayout(lines: lines, rules: [], crop: page.bounds(for: .cropBox))
        let parts = layout.caption(startingAt: best.caption, owner: best.graphic)
        let caption = PDFReferenceObjectLayout.Object(parts: parts).bounds
        let graphic = graphicBounds(including: best.graphic, caption: caption, spacing: best.caption.height,
                                    graphics: graphics, lines: lines)
        return (graphic, caption, parts)
    }

    private static func graphicBounds(including initial: CGRect, caption: CGRect, spacing: CGFloat,
                                      graphics: [CGRect], lines: [PDFReferenceTextLayout.Line]) -> CGRect {
        let envelope = initial.union(caption).insetBy(dx: -max(12, initial.width * 0.1), dy: 0)
        var bounds = initial
        var added = true
        while added {
            added = false
            for graphic in graphics where !bounds.contains(graphic) {
                let overlap = min(bounds.maxX, graphic.maxX) - max(bounds.minX, graphic.minX)
                let gap = max(graphic.minY - bounds.maxY, bounds.minY - graphic.maxY, 0)
                guard graphic.minY >= caption.maxY, graphic.minX >= envelope.minX, graphic.maxX <= envelope.maxX,
                      overlap >= min(bounds.width, graphic.width) * 0.5, gap <= max(12, spacing * 2) else { continue }
                let lower = min(bounds.maxY, graphic.maxY)
                let upper = max(bounds.minY, graphic.minY)
                let between = CGRect(x: max(bounds.minX, graphic.minX), y: lower,
                                     width: overlap, height: max(0, upper - lower))
                // Detached legends belong with the panels only across uninterrupted whitespace.
                guard !lines.contains(where: { between.height > 0 && $0.bounds.intersects(between) }) else { continue }
                bounds = bounds.union(graphic)
                added = true
            }
        }
        return bounds
    }

    private static func lineSegment(in range: NSRange, text: NSString, page: PDFPage) -> CGRect? {
        var bounds = CGRect.null
        var previous: CGRect?
        for index in range.location..<NSMaxRange(range) {
            guard !text.substring(with: NSRange(location: index, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let selection = page.selection(for: NSRange(location: index, length: 1)) else { continue }
            let glyph = selection.bounds(for: page)
            guard glyph.width > 0, glyph.height > 0 else { continue }
            if let previous {
                // PDFKit can merge adjacent columns into a single logical text line.
                if glyph.minX < previous.minX - 2 || glyph.minX - previous.maxX > max(12, bounds.height * 2)
                    || abs(glyph.midY - bounds.midY) > max(glyph.height, bounds.height) * 0.8 { break }
            }
            bounds = bounds.union(glyph)
            previous = glyph
        }
        return bounds.isNull ? nil : bounds
    }
}

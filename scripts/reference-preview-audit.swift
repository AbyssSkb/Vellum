import AppKit
import PDFKit
import CryptoKit

@main
@MainActor
enum ReferencePreviewAudit {
    static func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height].map(Double.init) }
    static func point(_ p: CGPoint) -> [Double] { [p.x, p.y].map(Double.init) }

    static func rawDestination(_ object: CGPDFObjectRef) -> String? {
        var string: CGPDFStringRef?
        if CGPDFObjectGetValue(object, .string, &string), let string { return CGPDFStringCopyTextString(string) as String? }
        var name: UnsafePointer<CChar>?
        if CGPDFObjectGetValue(object, .name, &name), let name { return String(cString: name) }
        var array: CGPDFArrayRef?
        if CGPDFObjectGetValue(object, .array, &array), let array {
            var parts: [String] = []
            for index in 0..<CGPDFArrayGetCount(array) {
                var entry: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, index, &entry), let entry else { continue }
                var value: CGPDFReal = 0
                if CGPDFObjectGetValue(entry, .real, &value) { parts.append(String(Double(value))); continue }
                var integer: CGPDFInteger = 0
                if CGPDFObjectGetValue(entry, .integer, &integer) { parts.append(String(integer)); continue }
                parts.append(rawDestination(entry) ?? String(describing: CGPDFObjectGetType(entry)))
            }
            return "[" + parts.joined(separator: " ") + "]"
        }
        return nil
    }

    static func rawLinks(on page: PDFPage) -> [(index: Int, bounds: CGRect, internalLink: Bool, destination: String?)] {
        guard let dictionary = page.pageRef?.dictionary else { return [] }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Annots", &array), let array else { return [] }
        return (0..<CGPDFArrayGetCount(array)).compactMap { index in
            var annotation: CGPDFDictionaryRef?, box: CGPDFArrayRef?, subtype: UnsafePointer<CChar>?
            guard CGPDFArrayGetDictionary(array, index, &annotation), let annotation,
                  CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Link",
                  CGPDFDictionaryGetArray(annotation, "Rect", &box), let box, CGPDFArrayGetCount(box) == 4 else { return nil }
            var values = [CGPDFReal](repeating: 0, count: 4)
            guard (0..<4).allSatisfy({ CGPDFArrayGetNumber(box, $0, &values[$0]) }) else { return nil }
            var destination: CGPDFObjectRef?
            var internalLink = CGPDFDictionaryGetObject(annotation, "Dest", &destination)
            if !internalLink {
                var action: CGPDFDictionaryRef?, kind: UnsafePointer<CChar>?
                if CGPDFDictionaryGetDictionary(annotation, "A", &action), let action,
                   CGPDFDictionaryGetName(action, "S", &kind), let kind, String(cString: kind) == "GoTo" {
                    internalLink = true
                    CGPDFDictionaryGetObject(action, "D", &destination)
                }
            }
            return (index, CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1]).standardized,
                    internalLink, destination.flatMap(rawDestination))
        }
    }

    static func render(_ page: PDFPage, to url: URL, scale: CGFloat = 2) throws {
        let geometry = PDFPageDisplayGeometry(page: page, box: .cropBox)
        let bounds = geometry.bounds
        guard bounds.width > 0, bounds.height > 0 else { throw NSError(domain: "audit", code: 1) }
        let scale = min(scale, 12000 / max(bounds.width, bounds.height))
        let width = max(1, Int(ceil(bounds.width * scale)))
        let height = max(1, Int(ceil(bounds.height * scale)))
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: image) else {
            throw NSError(domain: "audit", code: 2)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .cropBox, to: cg)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = image.representation(using: .png, properties: [:]) else { throw NSError(domain: "audit", code: 3) }
        try data.write(to: url)
    }

    static func selectedContext(_ annotation: PDFAnnotation, on page: PDFPage) -> String {
        guard let text = page.string as NSString?, let selection = page.selection(for: annotation.bounds),
              selection.numberOfTextRanges(on: page) > 0 else { return "" }
        let ranges = (0..<selection.numberOfTextRanges(on: page)).map { selection.range(at: $0, on: page) }
            .filter { $0.location != NSNotFound && NSMaxRange($0) <= text.length }
        guard let first = ranges.map(\.location).min(), let last = ranges.map(NSMaxRange).max() else { return "" }
        let start = max(0, first - 100), end = min(text.length, last + 100)
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    static func sameBounds(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 0.5 && abs(first.minY - second.minY) < 0.5
            && abs(first.width - second.width) < 0.5 && abs(first.height - second.height) < 0.5
    }

    static func jsonSafe(_ value: Any) -> Any {
        if let string = value as? NSString {
            let units = (0..<string.length).map { string.character(at: $0) }
            return String(decoding: units, as: UTF16.self)
        }
        if let array = value as? [Any] { return array.map(jsonSafe) }
        if let object = value as? [String: Any] { return object.mapValues(jsonSafe) }
        return value
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: native-audit PDF OUTPUT_DIR") }
        let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        for directory in ["crops", "source-pages"] { try fm.createDirectory(at: output.appendingPathComponent(directory), withIntermediateDirectories: true) }
        guard let document = PDFDocument(url: source) else { fatalError("Cannot open PDF: \(source.path)") }
        let start = Date()
        var rows: [[String: Any]] = [], pages: [[String: Any]] = []
        var cache: [String: String] = [:]
        var externalLinks = 0, rawCount = 0
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            try autoreleasepool {
                let pageImage = "source-pages/page-\(pageIndex + 1).png"
                try render(page, to: output.appendingPathComponent(pageImage), scale: 1.5)
                let raw = rawLinks(on: page)
                rawCount += raw.count
                externalLinks += raw.filter { !$0.internalLink }.count
                var matched = Set<Int>()
                var links: [(PDFAnnotation?, Int?, Int?, CGRect, String?)] = []
                for item in raw where item.internalLink {
                    let candidate = page.annotations.enumerated().first { element in
                        !matched.contains(element.offset) && element.element.type == "Link"
                            && sameBounds(element.element.bounds, item.bounds)
                    }
                    if let candidate { matched.insert(candidate.offset) }
                    links.append((candidate?.element, candidate?.offset, item.index, item.bounds, item.destination))
                }
                // PDFKit may expose internal annotations absent from the raw page dictionary.
                for (index, annotation) in page.annotations.enumerated() where !matched.contains(index) && annotation.type == "Link" {
                    if annotation.destination != nil || annotation.action is PDFActionGoTo {
                        links.append((annotation, index, nil, annotation.bounds, nil))
                    }
                }
                pages.append(["page": pageIndex + 1, "image": pageImage, "cropBox": rect(page.bounds(for: .cropBox)),
                    "rotation": page.rotation, "text": page.string ?? "", "rawLinkCount": raw.count,
                    "internalLinkCount": links.count])
                for (ordinal, item) in links.enumerated() {
                    let id = "p\(pageIndex + 1)-a\(item.1 ?? item.2 ?? ordinal)"
                    let began = Date()
                    var row: [String: Any] = ["id": id, "sourcePage": pageIndex + 1,
                        "sourceBounds": rect(item.3), "sourceImage": pageImage,
                        "annotationIndex": item.1.map { $0 as Any } ?? NSNull(), "rawAnnotationIndex": item.2.map { $0 as Any } ?? NSNull(),
                        "rawDestination": item.4 ?? "", "status": "unresolved"]
                    if let annotation = item.0 {
                        row["sourceText"] = page.selection(for: annotation.bounds)?.string ?? ""
                        row["sourceContext"] = selectedContext(annotation, on: page)
                        if let destination = PDFLinkNavigation.previewDestination(for: annotation, in: document), let target = destination.page {
                            row["targetPage"] = document.index(for: target) + 1
                            row["destinationPoint"] = point(destination.point)
                            var crop: CGRect?, continuation: (page: PDFPage, bounds: CGRect)?, title: AppText?
                            var additional: [(page: PDFPage, bounds: CGRect)] = []
                            var resolved = destination
                            var entire = false
                            switch PDFReferencePreview.resolve(for: annotation, destination: destination) {
                            case .region(let region):
                                crop = region.bounds; continuation = region.continuation; title = region.title
                                #if AUDIT_ADDITIONAL_FRAGMENTS
                                additional = region.additionalFragments
                                #endif
                                resolved = region.destination ?? destination; entire = true
                                row["resolution"] = "region"
                            case .pageContext: row["resolution"] = "pageContext"
                            }
                            let page = resolved.page ?? target
                            var fragments: [[String: Any]] = [["page": document.index(for: page) + 1,
                                "bounds": rect(crop ?? page.bounds(for: .cropBox))]]
                            if let continuation { fragments.append(["page": document.index(for: continuation.page) + 1, "bounds": rect(continuation.bounds)]) }
                            fragments += additional.map { ["page": document.index(for: $0.page) + 1, "bounds": rect($0.bounds)] }
                            row["fragments"] = fragments; row["title"] = title?.description ?? ""
                            row["resolvedPage"] = document.index(for: page) + 1
                            row["resolvedDestinationPoint"] = point(resolved.point)
                            #if AUDIT_ADDITIONAL_FRAGMENTS
                            let content = PDFReferenceContent(document: document, destination: resolved, crop: crop,
                                fitsEntireCrop: entire, title: title, continuation: continuation, additionalFragments: additional)
                            #else
                            let content = PDFReferenceContent(document: document, destination: resolved, crop: crop,
                                fitsEntireCrop: entire, title: title, continuation: continuation)
                            #endif
                            if let content {
                                row["contentDestinationPoint"] = point(content.destination.point)
                                let keyData = try JSONSerialization.data(withJSONObject: ["fragments": fragments, "title": title?.description ?? "", "entire": entire], options: [.sortedKeys])
                                let key = SHA256.hash(data: keyData).map { String(format: "%02x", $0) }.joined()
                                let file = "crops/\(id).png"
                                if let previous = cache[key] {
                                    try fm.linkItem(at: output.appendingPathComponent(previous), to: output.appendingPathComponent(file))
                                } else {
                                    try render(content.displayPage, to: output.appendingPathComponent(file))
                                    cache[key] = file
                                }
                                row["status"] = "generated"; row["image"] = file; row["outputKey"] = key
                                row["displayBounds"] = rect(content.displayPage.bounds(for: .cropBox))
                                row["displayText"] = content.displayPage.selection(for: content.displayPage.bounds(for: .cropBox))?.string ?? ""
                            } else { row["status"] = "content_failed" }
                        }
                    }
                    row["milliseconds"] = Date().timeIntervalSince(began) * 1000
                    rows.append(row)
                }
                print("\(source.lastPathComponent) page \(pageIndex + 1)/\(document.pageCount): \(links.count) internal")
                fflush(stdout)
            }
        }
        // Do not attach a quality grade here: rendering is coverage, not correctness.
        let result: [String: Any] = ["source": source.path, "pageCount": document.pageCount,
            "sourceSHA256": SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined(),
            "rawLinkCount": rawCount, "externalLinkCount": externalLinks, "internalLinkCount": rows.count,
            "generatedCount": rows.filter { $0["status"] as? String == "generated" }.count,
            "distinctOutputCount": cache.count, "seconds": Date().timeIntervalSince(start), "pages": pages, "links": rows]
        let data = try JSONSerialization.data(withJSONObject: jsonSafe(result), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        try data.write(to: output.appendingPathComponent("native-results.json"))
        print("Finished \(source.lastPathComponent): \(rows.count) internal links, \(cache.count) distinct outputs")
    }
}

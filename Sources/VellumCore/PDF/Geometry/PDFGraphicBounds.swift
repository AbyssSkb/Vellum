import CoreGraphics

enum PDFGraphicBounds {
    // shortcut: Direct page paths and nonrectangular clips need layout analysis when no XObject bounds exist.
    static func regions(on page: CGPDFPage) -> [CGRect] {
        scan(page).regions
    }

    static func layoutRules(on page: CGPDFPage) -> [CGRect] {
        scan(page).rules
    }

    private static func scan(_ page: CGPDFPage) -> Result {
        guard let dictionary = page.dictionary,
              let resources = inheritedResources(in: dictionary) else { return Result() }
        let crop = page.getBoxRect(.cropBox)
        let state = ScanState(resources: resources, transform: .identity, clip: crop, crop: crop)
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, state: state)
        return state.result
    }

    private final class Result {
        var regions: [CGRect] = []
        var rules: [CGRect] = []
        var activeForms: Set<CGPDFStreamRef> = []
    }

    private final class ScanState {
        enum Path {
            case empty, rectangle(CGRect), points([CGPoint]), unsupported
        }

        let resources: CGPDFDictionaryRef
        var transform: CGAffineTransform
        var unsupportedClip = false
        var stack: [(CGAffineTransform, CGRect, Bool)] = []
        var clip: CGRect
        var path = Path.empty
        var encounteredClip = false
        var encounteredUnknownClip = false
        var hasDirectMarks = false
        let crop: CGRect
        let depth: Int
        let result: Result

        init(resources: CGPDFDictionaryRef, transform: CGAffineTransform, clip: CGRect,
             crop: CGRect, depth: Int = 0, result: Result = Result()) {
            self.resources = resources
            self.transform = transform
            self.clip = clip
            self.crop = crop
            self.depth = depth
            self.result = result
        }

        func append(_ rect: CGRect, isForm: Bool) {
            guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return }
            let rect = rect.intersection(clip).intersection(crop)
            guard !rect.isNull, !rect.isInfinite, rect.width > 1, rect.height > 1 else { return }
            // Page-sized Forms are usually export wrappers, not an individual figure.
            guard !isForm || rect.width < crop.width * 0.9 || rect.height < crop.height * 0.9 else { return }
            guard !result.regions.contains(where: {
                abs($0.minX - rect.minX) < 0.25 && abs($0.minY - rect.minY) < 0.25
                    && abs($0.width - rect.width) < 0.25 && abs($0.height - rect.height) < 0.25
            }) else { return }
            result.regions.append(rect)
        }

        func paintPath(stroked: Bool) {
            switch path {
            case .empty: return
            default: hasDirectMarks = true
            }
            defer { path = .empty }
            guard !unsupportedClip else { return }
            let bounds: CGRect
            switch path {
            case .rectangle(let rect): bounds = rect
            case .points(let points) where points.count == 2 && stroked:
                let first = points[0], last = points[1]
                guard abs(first.x - last.x) < 0.001 || abs(first.y - last.y) < 0.001 else { return }
                bounds = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                width: abs(first.x - last.x), height: abs(first.y - last.y))
            case .points(let points):
                guard let rect = PDFGraphicBounds.rectangle(for: points) else { return }
                bounds = rect
            default: return
            }
            guard stroked || (bounds.width > 0 && bounds.height > 0),
                  max(bounds.width, bounds.height) >= 12, min(bounds.width, bounds.height) <= 3 else { return }
            let rect = bounds.insetBy(dx: bounds.width == 0 ? -0.25 : 0,
                                      dy: bounds.height == 0 ? -0.25 : 0)
                .intersection(clip).intersection(crop)
            guard !rect.isNull, !rect.isInfinite, max(rect.width, rect.height) >= 12,
                  !result.rules.contains(where: {
                      abs($0.minX - rect.minX) < 0.25 && abs($0.minY - rect.minY) < 0.25
                          && abs($0.width - rect.width) < 0.25 && abs($0.height - rect.height) < 0.25
                  }) else { return }
            result.rules.append(rect)
        }
    }

    private static func scan(_ content: CGPDFContentStreamRef, state: ScanState) {
        guard let table = CGPDFOperatorTableCreate() else { return }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            state.stack.append((state.transform, state.clip, state.unsupportedClip))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            if let (transform, clip, unsupportedClip) = state.stack.popLast() {
                state.transform = transform
                state.clip = clip
                state.unsupportedClip = unsupportedClip
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            var values = [CGPDFReal](repeating: 0, count: 4)
            for index in (0..<4).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]), values[index].isFinite else {
                    state.path = .unsupported
                    return
                }
            }
            let transform = state.transform
            guard case .empty = state.path,
                  (transform.b == 0 && transform.c == 0) || (transform.a == 0 && transform.d == 0) else {
                state.path = .unsupported
                return
            }
            let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                .standardized.applying(transform)
            state.path = [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                ? .rectangle(rect) : .unsupported
        }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            guard case .empty = state.path,
                  let point = PDFGraphicBounds.pathPoint(scanner, transform: state.transform) else {
                state.path = .unsupported
                return
            }
            state.path = .points([point])
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            guard case .points(var points) = state.path, points.count < 4,
                  let point = PDFGraphicBounds.pathPoint(scanner, transform: state.transform) else {
                state.path = .unsupported
                return
            }
            points.append(point)
            state.path = .points(points)
        }
        CGPDFOperatorTableSetCallback(table, "h") { _, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            switch state.path {
            case .rectangle: break
            case .points(let points) where points.count == 4: break
            default: state.path = .unsupported
            }
        }
        for name in ["c", "v", "y"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                guard let info else { return }
                Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue().path = .unsupported
            }
        }
        for name in ["W", "W*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                guard let info else { return }
                let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
                state.encounteredClip = true
                let rectangle: CGRect?
                switch state.path {
                case .rectangle(let rect): rectangle = rect
                case .points(let points): rectangle = PDFGraphicBounds.rectangle(for: points)
                default: rectangle = nil
                }
                if let rect = rectangle {
                    state.clip = state.clip.intersection(rect)
                } else {
                    state.unsupportedClip = true
                    state.encounteredUnknownClip = true
                }
            }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in
            guard let info else { return }
            Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue().path = .empty
        }
        for name in ["S", "s", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                guard let info else { return }
                Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue().paintPath(stroked: true)
            }
        }
        for name in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                guard let info else { return }
                Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue().paintPath(stroked: false)
            }
        }
        for name in ["Tj", "TJ", "'", "\"", "sh"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                guard let info else { return }
                Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue().hasDirectMarks = true
            }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]), values[index].isFinite else { return }
            }
            let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                                           d: values[3], tx: values[4], ty: values[5])
            state.transform = matrix.concatenating(state.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScanState>.fromOpaque(info).takeUnretainedValue()
            guard !state.unsupportedClip else { return }
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name)
            else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else { return }
            PDFGraphicBounds.draw(stream, dictionary: dictionary, parent: CGPDFScannerGetContentStream(scanner), state: state)
        }
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(state).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        CGPDFScannerScan(scanner)
    }

    private static func draw(_ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef,
                             parent: CGPDFContentStreamRef, state: ScanState) {
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
        switch String(cString: subtype) {
        case "Image":
            state.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(state.transform), isForm: false)
        case "Form":
            guard state.depth < 24, !state.result.activeForms.contains(stream),
                  let box = numbers(in: dictionary, key: "BBox", count: 4) else { return }
            state.result.activeForms.insert(stream)
            defer { state.result.activeForms.remove(stream) }
            let bbox = CGRect(x: box[0], y: box[1], width: box[2] - box[0], height: box[3] - box[1]).standardized
            var transform = state.transform
            if let matrix = numbers(in: dictionary, key: "Matrix", count: 6) {
                transform = CGAffineTransform(a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3],
                                              tx: matrix[4], ty: matrix[5]).concatenating(transform)
            }
            let bounds = bbox.applying(transform)
            guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else { return }
            let regionStart = state.result.regions.count
            let ruleStart = state.result.rules.count
            var ownResources: CGPDFDictionaryRef?
            CGPDFDictionaryGetDictionary(dictionary, "Resources", &ownResources)
            let resources = ownResources ?? state.resources
            let child = ScanState(resources: resources, transform: transform,
                                  clip: bounds.intersection(state.clip), crop: state.crop,
                                  depth: state.depth + 1, result: state.result)
            let content = CGPDFContentStreamCreateWithStream(stream, resources, parent)
            defer { CGPDFContentStreamRelease(content) }
            scan(content, state: child)
            state.encounteredClip = state.encounteredClip || child.encounteredClip
            if child.encounteredUnknownClip {
                state.result.regions.removeSubrange(regionStart...)
                state.result.rules.removeSubrange(ruleStart...)
                state.encounteredUnknownClip = true
            } else if !child.encounteredClip || child.hasDirectMarks {
                state.append(bounds, isForm: true)
            }
        default:
            break
        }
    }

    private static func pathPoint(_ scanner: CGPDFScannerRef, transform: CGAffineTransform) -> CGPoint? {
        var x: CGPDFReal = 0
        var y: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x),
              x.isFinite, y.isFinite else { return nil }
        let point = CGPoint(x: x, y: y).applying(transform)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    private static func rectangle(for points: [CGPoint]) -> CGRect? {
        guard points.count == 4 else { return nil }
        let minX = points.map(\.x).min()!
        let minY = points.map(\.y).min()!
        let maxX = points.map(\.x).max()!
        let maxY = points.map(\.y).max()!
        let tolerance: CGFloat = 0.001
        guard maxX - minX > tolerance, maxY - minY > tolerance else { return nil }
        var corners = Set<Int>()
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % 4]
            guard abs(point.x - next.x) <= tolerance || abs(point.y - next.y) <= tolerance else { return nil }
            let left = abs(point.x - minX) <= tolerance
            let bottom = abs(point.y - minY) <= tolerance
            guard left || abs(point.x - maxX) <= tolerance,
                  bottom || abs(point.y - maxY) <= tolerance else { return nil }
            corners.insert((left ? 0 : 1) + (bottom ? 0 : 2))
        }
        guard corners.count == 4 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func numbers(in dictionary: CGPDFDictionaryRef, key: String, count: Int) -> [CGFloat]? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &array), let array,
              CGPDFArrayGetCount(array) == count else { return nil }
        var values = [CGFloat](repeating: 0, count: count)
        for index in 0..<count {
            guard CGPDFArrayGetNumber(array, index, &values[index]), values[index].isFinite else { return nil }
        }
        return values
    }

    private static func inheritedResources(in dictionary: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var current = dictionary
        for _ in 0..<32 {
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources) { return resources }
            var parent: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(current, "Parent", &parent), let parent else { return nil }
            current = parent
        }
        return nil
    }
}

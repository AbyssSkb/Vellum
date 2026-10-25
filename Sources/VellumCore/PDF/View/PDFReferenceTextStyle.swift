import CoreGraphics

enum PDFReferenceTextStyle {
    // shortcut: Forms, unknown graphics states, and unsupported text positioning yield no evidence; extend only with reliable visibility and positioning.
    static func boldLineStarts(on page: CGPDFPage) -> [CGPoint] {
        let state = State()
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            state.stack.append((state.transform, state.bold, state.leading, state.rise, state.rendering,
                                state.graphicsEvidenceUnsafe, state.horizontalScale))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let state = PDFReferenceTextStyle.context(info), let saved = state.stack.popLast() else { return }
            (state.transform, state.bold, state.leading, state.rise, state.rendering,
             state.graphicsEvidenceUnsafe, state.horizontalScale) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info), let values = PDFReferenceTextStyle.numbers(scanner, count: 6) else { return }
            state.transform = PDFReferenceTextStyle.matrix(values).concatenating(state.transform)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            state.line = .identity
            state.lastShown = nil
            state.ready = false
        }
        CGPDFOperatorTableSetCallback(table, "ET") { _, info in PDFReferenceTextStyle.context(info)?.ready = false }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info), let values = PDFReferenceTextStyle.numbers(scanner, count: 6) else { return }
            state.position(PDFReferenceTextStyle.matrix(values))
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info), let values = PDFReferenceTextStyle.numbers(scanner, count: 2) else { return }
            state.move(x: values[0], y: values[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info), let values = PDFReferenceTextStyle.numbers(scanner, count: 2) else { return }
            state.leading = -values[1]
            state.move(x: values[0], y: values[1])
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            guard let value = PDFReferenceTextStyle.numbers(scanner, count: 1)?.first else { return }
            PDFReferenceTextStyle.context(info)?.leading = value
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            state.move(x: 0, y: -state.leading)
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            var size: CGPDFReal = 0, name: UnsafePointer<CChar>?
            state.bold = false
            guard CGPDFScannerPopNumber(scanner, &size), size > 0, size.isFinite,
                  CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name)
            else { return }
            var font: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(object, .dictionary, &font), let font { state.bold = PDFReferenceTextStyle.isBold(font) }
        }
        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, info in
            guard let value = PDFReferenceTextStyle.numbers(scanner, count: 1)?.first else { return }
            PDFReferenceTextStyle.context(info)?.rendering = value
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            guard let value = PDFReferenceTextStyle.numbers(scanner, count: 1)?.first else { return }
            PDFReferenceTextStyle.context(info)?.rise = value
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            PDFReferenceTextStyle.context(info)?.horizontalScale = PDFReferenceTextStyle.numbers(scanner, count: 1)?.first ?? 0
        }
        CGPDFOperatorTableSetCallback(table, "gs") { _, info in
            PDFReferenceTextStyle.context(info)?.graphicsEvidenceUnsafe = true
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            if CGPDFStringGetLength(string) > 0 { PDFReferenceTextStyle.context(info)?.show() }
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            for index in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                if CGPDFArrayGetString(array, index, &string), let string, CGPDFStringGetLength(string) > 0 {
                    state.show()
                    break
                }
                var offset: CGPDFReal = 0
                if CGPDFArrayGetNumber(array, index, &offset), offset != 0 { state.ready = false }
            }
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            state.move(x: 0, y: -state.leading)
            if CGPDFStringGetLength(string) > 0 { state.show() }
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            guard let state = PDFReferenceTextStyle.context(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string,
                  PDFReferenceTextStyle.numbers(scanner, count: 2) != nil else { return }
            state.move(x: 0, y: -state.leading)
            if CGPDFStringGetLength(string) > 0 { state.show() }
        }
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(state).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        return CGPDFScannerScan(scanner) ? state.starts : []
    }

    private final class State {
        var transform = CGAffineTransform.identity
        var line = CGAffineTransform.identity
        var bold = false, ready = false, graphicsEvidenceUnsafe = false
        var leading: CGFloat = 0, rise: CGFloat = 0, rendering: CGFloat = 0
        var horizontalScale: CGFloat = 100
        var lastShown: CGPoint?
        var stack: [(CGAffineTransform, Bool, CGFloat, CGFloat, CGFloat, Bool, CGFloat)] = []
        var starts: [CGPoint] = []

        func position(_ matrix: CGAffineTransform) {
            line = matrix
            let point = CGPoint.zero.applying(line).applying(transform)
            ready = lastShown.map { abs($0.y - point.y) > 0.5 } ?? true
        }

        func move(x: CGFloat, y: CGFloat) {
            position(CGAffineTransform(translationX: x, y: y).concatenating(line))
        }

        func show() {
            let matrix = line.concatenating(transform)
            let point = CGPoint.zero.applying(matrix)
            defer { ready = false; lastShown = point }
            guard ready, bold, !graphicsEvidenceUnsafe, rise == 0, (0...2).contains(rendering),
                  horizontalScale.isFinite, horizontalScale > 0,
                  matrix.a > 0, matrix.d > 0, abs(matrix.b) < 0.001, abs(matrix.c) < 0.001,
                  point.x.isFinite, point.y.isFinite else { return }
            starts.append(point)
        }
    }

    private static func context(_ info: UnsafeMutableRawPointer?) -> State? {
        info.map { Unmanaged<State>.fromOpaque($0).takeUnretainedValue() }
    }

    private static func numbers(_ scanner: CGPDFScannerRef, count: Int) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for index in (0..<count).reversed() {
            guard CGPDFScannerPopNumber(scanner, &values[index]), values[index].isFinite else { return nil }
        }
        return values
    }

    private static func matrix(_ values: [CGFloat]) -> CGAffineTransform {
        CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }

    private static func isBold(_ font: CGPDFDictionaryRef) -> Bool {
        func boldName(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Bool {
            var name: UnsafePointer<CChar>?
            return CGPDFDictionaryGetName(dictionary, key, &name)
                && name.map { String(cString: $0).lowercased().contains("bold") } == true
        }
        func metadataIsBold(_ font: CGPDFDictionaryRef) -> Bool {
            if boldName(font, "BaseFont") { return true }
            var descriptor: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(font, "FontDescriptor", &descriptor), let descriptor else { return false }
            if boldName(descriptor, "FontName") { return true }
            var weight: CGPDFReal = 0
            if CGPDFDictionaryGetNumber(descriptor, "FontWeight", &weight), weight.isFinite, weight >= 700 { return true }
            var flags: CGPDFInteger = 0
            return CGPDFDictionaryGetInteger(descriptor, "Flags", &flags) && flags >= 0 && flags & (1 << 18) != 0
        }
        if metadataIsBold(font) { return true }
        var descendants: CGPDFArrayRef?, child: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
              CGPDFArrayGetCount(descendants) == 1, CGPDFArrayGetDictionary(descendants, 0, &child), let child else { return false }
        return metadataIsBold(child)
    }
}

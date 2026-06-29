@preconcurrency import AppKit

struct ReaderSnapshot: Codable, Equatable {
    static let initial = ReaderSnapshot(
        pageIndex: 0,
        pointOnPage: .zero,
        scrollOrigin: nil,
        scaleFactor: 0,
        autoScales: true
    )

    var pageIndex: Int
    var pointOnPage: NSPoint
    var scrollOrigin: NSPoint?
    var scaleFactor: CGFloat
    var autoScales: Bool

    private enum CodingKeys: String, CodingKey {
        case pageIndex
        case pointOnPageX
        case pointOnPageY
        case scrollOriginX
        case scrollOriginY
        case scaleFactor
        case autoScales
    }

    init(
        pageIndex: Int,
        pointOnPage: NSPoint,
        scrollOrigin: NSPoint?,
        scaleFactor: CGFloat,
        autoScales: Bool
    ) {
        self.pageIndex = pageIndex
        self.pointOnPage = pointOnPage
        self.scrollOrigin = scrollOrigin
        self.scaleFactor = scaleFactor
        self.autoScales = autoScales
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        pointOnPage = NSPoint(
            x: try container.decode(CGFloat.self, forKey: .pointOnPageX),
            y: try container.decode(CGFloat.self, forKey: .pointOnPageY)
        )

        if let x = try container.decodeIfPresent(CGFloat.self, forKey: .scrollOriginX),
           let y = try container.decodeIfPresent(CGFloat.self, forKey: .scrollOriginY) {
            scrollOrigin = NSPoint(x: x, y: y)
        } else {
            scrollOrigin = nil
        }

        scaleFactor = try container.decode(CGFloat.self, forKey: .scaleFactor)
        autoScales = try container.decode(Bool.self, forKey: .autoScales)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageIndex, forKey: .pageIndex)
        try container.encode(pointOnPage.x, forKey: .pointOnPageX)
        try container.encode(pointOnPage.y, forKey: .pointOnPageY)
        try container.encodeIfPresent(scrollOrigin?.x, forKey: .scrollOriginX)
        try container.encodeIfPresent(scrollOrigin?.y, forKey: .scrollOriginY)
        try container.encode(scaleFactor, forKey: .scaleFactor)
        try container.encode(autoScales, forKey: .autoScales)
    }
}

@preconcurrency import AppKit

struct ReaderSnapshot: Equatable {
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
}

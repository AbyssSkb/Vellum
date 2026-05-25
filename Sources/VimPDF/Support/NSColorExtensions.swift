@preconcurrency import AppKit

extension NSColor {
    func persistentHighlightColor() -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return withAlphaComponent(1)
        }

        let sourceOpacity: CGFloat = 0.42
        return NSColor(
            calibratedRed: rgb.redComponent * sourceOpacity + (1 - sourceOpacity),
            green: rgb.greenComponent * sourceOpacity + (1 - sourceOpacity),
            blue: rgb.blueComponent * sourceOpacity + (1 - sourceOpacity),
            alpha: 1
        )
    }
}

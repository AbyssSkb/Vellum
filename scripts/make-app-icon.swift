import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let sourcePath = CommandLine.arguments.dropFirst(2).first ?? "Resources/AppIcon/icon.png"
let sourceURL = URL(fileURLWithPath: sourcePath)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "VellumIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not load \(sourcePath)"]
    )
}
let sourceRect = NSRect(origin: .zero, size: sourceImage.size)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in icons {
    let image = resize(sourceImage, from: sourceRect, pixels: icon.pixels)
    let url = outputDirectory.appendingPathComponent(icon.name)
    guard let data = image.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "VellumIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode \(icon.name)"]
        )
    }
    try data.write(to: url)
}

func resize(_ sourceImage: NSImage, from sourceRect: NSRect, pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: sourceRect,
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

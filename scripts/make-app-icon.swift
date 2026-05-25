import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let sourceURL = URL(fileURLWithPath: "icon.png")

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "VimPDFIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not load icon.png"]
    )
}
let sourceRect = visibleSourceRect(in: sourceImage)

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
            domain: "VimPDFIcon",
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

func visibleSourceRect(in image: NSImage) -> NSRect {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let bytes = CFDataGetBytePtr(data) else {
        return NSRect(origin: .zero, size: image.size)
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = cgImage.bytesPerRow
    let bitsPerPixel = cgImage.bitsPerPixel
    let bitsPerComponent = cgImage.bitsPerComponent
    guard bitsPerPixel == 32, bitsPerComponent == 8 else {
        return NSRect(origin: .zero, size: image.size)
    }

    let alphaInfo = cgImage.alphaInfo
    let alphaOffset: Int
    switch alphaInfo {
    case .premultipliedLast, .last:
        alphaOffset = 3
    case .premultipliedFirst, .first:
        alphaOffset = 0
    default:
        return NSRect(origin: .zero, size: image.size)
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    let alphaThreshold: UInt8 = 8

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4 + alphaOffset
            if bytes[offset] > alphaThreshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return NSRect(origin: .zero, size: image.size)
    }

    let cropWidth = maxX - minX + 1
    let cropHeight = maxY - minY + 1
    let side = max(cropWidth, cropHeight)
    let centerX = CGFloat(minX + maxX) / 2
    let centerY = CGFloat(minY + maxY) / 2
    var originX = centerX - CGFloat(side) / 2
    var originY = centerY - CGFloat(side) / 2
    originX = min(max(0, originX), CGFloat(width - side))
    originY = min(max(0, originY), CGFloat(height - side))

    return NSRect(
        x: originX,
        y: originY,
        width: CGFloat(side),
        height: CGFloat(side)
    )
}

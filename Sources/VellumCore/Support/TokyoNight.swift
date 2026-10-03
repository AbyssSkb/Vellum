@preconcurrency import AppKit
import SwiftUI

public enum TokyoNight {
    public static var background: NSColor { color(0x151517) }
    public static var backgroundDeep: NSColor { color(0x101012) }
    public static var panel: NSColor { color(0x1B1B1E) }
    public static var panelElevated: NSColor { color(0x242427) }
    public static var selection: NSColor { color(0x303034) }
    public static var border: NSColor { color(0x343438) }
    public static var foreground: NSColor { color(0xDFDFE4) }
    public static var muted: NSColor { color(0x9B9BA3) }
    public static var blue: NSColor { color(0x8784C3) }
    public static var cyan: NSColor { color(0x7DCFFF) }
    public static var purple: NSColor { color(0xBB9AF7) }
    public static var red: NSColor { color(0xF7768E) }

    public static var backgroundColor: Color { Color(nsColor: background) }
    public static var backgroundDeepColor: Color { Color(nsColor: backgroundDeep) }
    public static var panelColor: Color { Color(nsColor: panel) }
    public static var panelElevatedColor: Color { Color(nsColor: panelElevated) }
    public static var selectionColor: Color { Color(nsColor: selection) }
    public static var borderColor: Color { Color(nsColor: border) }
    public static var foregroundColor: Color { Color(nsColor: foreground) }
    public static var mutedColor: Color { Color(nsColor: muted) }
    public static var blueColor: Color { Color(nsColor: blue) }
    public static var cyanColor: Color { Color(nsColor: cyan) }
    public static var redColor: Color { Color(nsColor: red) }

    static func cssHex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }

    private static func color(_ hex: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct TokyoNightDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis

    var body: some View {
        Rectangle()
            .fill(TokyoNight.borderColor.opacity(0.6))
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

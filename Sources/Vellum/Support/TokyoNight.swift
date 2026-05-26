@preconcurrency import AppKit
import SwiftUI

enum TokyoNight {
    static var background: NSColor { color(0x1A1B26) }
    static var backgroundDeep: NSColor { color(0x16161E) }
    static var panel: NSColor { color(0x24283B) }
    static var panelElevated: NSColor { color(0x292E42) }
    static var selection: NSColor { color(0x33467C) }
    static var border: NSColor { color(0x3B4261) }
    static var foreground: NSColor { color(0xC0CAF5) }
    static var muted: NSColor { color(0x565F89) }
    static var blue: NSColor { color(0x7AA2F7) }
    static var cyan: NSColor { color(0x7DCFFF) }
    static var purple: NSColor { color(0xBB9AF7) }
    static var red: NSColor { color(0xF7768E) }

    static var backgroundColor: Color { Color(nsColor: background) }
    static var backgroundDeepColor: Color { Color(nsColor: backgroundDeep) }
    static var panelColor: Color { Color(nsColor: panel) }
    static var panelElevatedColor: Color { Color(nsColor: panelElevated) }
    static var selectionColor: Color { Color(nsColor: selection) }
    static var borderColor: Color { Color(nsColor: border) }
    static var foregroundColor: Color { Color(nsColor: foreground) }
    static var mutedColor: Color { Color(nsColor: muted) }
    static var blueColor: Color { Color(nsColor: blue) }
    static var cyanColor: Color { Color(nsColor: cyan) }
    static var redColor: Color { Color(nsColor: red) }

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
            .fill(TokyoNight.borderColor.opacity(0.75))
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

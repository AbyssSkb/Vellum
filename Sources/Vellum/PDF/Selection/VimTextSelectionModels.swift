@preconcurrency import AppKit

struct VimTextSelectionNavigationState {
    var anchorOffset: Int
    var extentOffset: Int
    var preferredX: CGFloat?
    var anchorCaret: VimTextCaret?
    var extentCaret: VimTextCaret?
}

struct VimTextCaret {
    let offset: Int
    let pageIndex: Int
    let slotIndex: Int
    let point: NSPoint
    let lineMidY: CGFloat
}

struct VimTextLineCharacter {
    let globalOffset: Int
    let minX: CGFloat
    let centerX: CGFloat
    let maxX: CGFloat
    let centerY: CGFloat
    let height: CGFloat
}

struct VimTextLine {
    let pageIndex: Int
    let startOffset: Int
    let endOffset: Int
    let midY: CGFloat
    let characters: [VimTextLineCharacter]
}

struct VimTextCaretPosition {
    let pageIndex: Int
    let lineIndex: Int
    let slotIndex: Int
}

enum VimTextCharacterClass: Equatable {
    case whitespace
    case word
    case punctuation
}

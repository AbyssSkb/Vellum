import Foundation

struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let items: [ShortcutItem]
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: [String]
    let action: String
}

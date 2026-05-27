@preconcurrency import AppKit
import Testing
@testable import VellumCore

@Suite("Search command")
struct SearchCommandTests {
    @Test
    func fieldEditorCommandsMapEnterAndEscape() {
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.insertNewline(_:))
            ) == .commit
        )
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            ) == .commit
        )
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.cancelOperation(_:))
            ) == .cancel
        )
    }

    @Test
    func unrelatedFieldEditorCommandsAreIgnored() {
        #expect(
            SearchCommandEditingCommand.action(
                for: #selector(NSResponder.moveDown(_:))
            ) == nil
        )
    }
}

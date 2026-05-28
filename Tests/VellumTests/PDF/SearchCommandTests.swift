@preconcurrency import AppKit
import Testing
@testable import VellumCore

@Suite("Search command")
struct SearchCommandTests {
    @Test
    func resultNavigatorChoosesLaterResultOnSamePage() {
        let locations = [
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 760, width: 60, height: 16),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 500, width: 60, height: 16),
                documentOrder: 1
            ),
            SearchResultLocation(
                pageIndex: 3,
                boundsInPage: NSRect(x: 20, y: 780, width: 60, height: 16),
                documentOrder: 2
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 2, pointInPage: NSPoint(x: 0, y: 620)),
            in: locations
        )

        #expect(index == 1)
    }

    @Test
    func resultNavigatorFallsThroughToLaterPage() {
        let locations = [
            SearchResultLocation(
                pageIndex: 2,
                boundsInPage: NSRect(x: 20, y: 760, width: 60, height: 16),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 3,
                boundsInPage: NSRect(x: 20, y: 780, width: 60, height: 16),
                documentOrder: 1
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 2, pointInPage: NSPoint(x: 0, y: 100)),
            in: locations
        )

        #expect(index == 1)
    }

    @Test
    func resultNavigatorUsesXPositionOnSameLine() {
        let locations = [
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 40, y: 300, width: 40, height: 18),
                documentOrder: 0
            ),
            SearchResultLocation(
                pageIndex: 1,
                boundsInPage: NSRect(x: 160, y: 300, width: 40, height: 18),
                documentOrder: 1
            )
        ]

        let index = SearchResultNavigator.firstIndex(
            atOrAfter: SearchAnchor(pageIndex: 1, pointInPage: NSPoint(x: 100, y: 309)),
            in: locations
        )

        #expect(index == 1)
    }

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

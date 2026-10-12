import Testing
@testable import VellumCore

@Suite("Page overview window")
struct PageOverviewWindowTests {
    @Test(arguments: [3, 9])
    func selectedPageStaysInCenterSlot(visibleCount: Int) {
        let slots = PageOverviewWindow.slots(selectedIndex: 12, pageCount: 40, visibleCount: visibleCount)
        let expected: [Int?] = visibleCount == 3 ? [11, 12, 13] : [8, 9, 10, 11, 12, 13, 14, 15, 16]
        #expect(slots == expected)
    }

    @Test(arguments: [3, 9])
    func edgePagesKeepSelectionCenteredWithEmptySlots(visibleCount: Int) {
        let firstPageSlots = PageOverviewWindow.slots(selectedIndex: 0, pageCount: 40, visibleCount: visibleCount)
        let lastPageSlots = PageOverviewWindow.slots(selectedIndex: 39, pageCount: 40, visibleCount: visibleCount)
        let firstExpected: [Int?] = visibleCount == 3 ? [nil, 0, 1] : [nil, nil, nil, nil, 0, 1, 2, 3, 4]
        let lastExpected: [Int?] = visibleCount == 3 ? [38, 39, nil] : [35, 36, 37, 38, 39, nil, nil, nil, nil]
        #expect(firstPageSlots == firstExpected)
        #expect(lastPageSlots == lastExpected)
    }
}

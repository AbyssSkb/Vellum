import Testing
@testable import VellumCore

@Suite("Page overview window")
struct PageOverviewWindowTests {
    @Test
    func selectedPageStaysInCenterSlot() {
        let slots = PageOverviewWindow.slots(selectedIndex: 12, pageCount: 40, visibleCount: 9)

        #expect(slots[4] == 12)
        #expect(slots == [8, 9, 10, 11, 12, 13, 14, 15, 16])
    }

    @Test
    func edgePagesKeepSelectionCenteredWithEmptySlots() {
        let firstPageSlots = PageOverviewWindow.slots(selectedIndex: 0, pageCount: 40, visibleCount: 9)
        let lastPageSlots = PageOverviewWindow.slots(selectedIndex: 39, pageCount: 40, visibleCount: 9)

        #expect(firstPageSlots[4] == 0)
        #expect(firstPageSlots == [nil, nil, nil, nil, 0, 1, 2, 3, 4])
        #expect(lastPageSlots[4] == 39)
        #expect(lastPageSlots == [35, 36, 37, 38, 39, nil, nil, nil, nil])
    }
}

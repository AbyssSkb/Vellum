import Foundation
import Testing
@testable import VellumCore

@MainActor
@Suite("Open URL relay")
struct OpenURLRelayTests {
    @Test
    func pendingFileURLsAreDeliveredOnActivation() {
        let relay = OpenURLRelay(currentTime: { 100 })
        let fileURL = URL(fileURLWithPath: "/tmp/a.pdf")
        let webURL = URL(string: "https://example.com/a.pdf")!
        var deliveries: [[URL]] = []

        relay.open([fileURL, fileURL, webURL])
        relay.activate { deliveries.append($0) }

        #expect(deliveries == [[fileURL.standardizedFileURL]])
    }

    @Test
    func activeHandlerReceivesUniqueFileURLsImmediately() {
        let relay = OpenURLRelay(currentTime: { 100 })
        let firstURL = URL(fileURLWithPath: "/tmp/a.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/b.pdf")
        var deliveries: [[URL]] = []

        relay.activate { deliveries.append($0) }
        relay.open([firstURL, secondURL, firstURL])

        #expect(deliveries == [[
            firstURL.standardizedFileURL,
            secondURL.standardizedFileURL
        ]])
    }

    @Test
    func recentDuplicateDeliveriesAreSuppressedBriefly() {
        var now: TimeInterval = 100
        let relay = OpenURLRelay(currentTime: { now })
        let fileURL = URL(fileURLWithPath: "/tmp/a.pdf")
        var deliveries: [[URL]] = []

        relay.activate { deliveries.append($0) }
        relay.open([fileURL])

        now = 100.4
        relay.open([fileURL])

        now = 100.6
        relay.open([fileURL])

        #expect(deliveries == [
            [fileURL.standardizedFileURL],
            [fileURL.standardizedFileURL]
        ])
    }
}

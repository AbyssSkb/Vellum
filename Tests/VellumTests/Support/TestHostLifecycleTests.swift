import CoreFoundation
import Foundation
import Testing

struct TestHostLifecycleTests {
    @Test @MainActor
    func stoppingMainRunLoopDoesNotEndTheTestRun() async throws {
        var stopped = false
        DispatchQueue.main.async {
            stopped = true
            CFRunLoopStop(CFRunLoopGetMain())
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(stopped)
    }
}

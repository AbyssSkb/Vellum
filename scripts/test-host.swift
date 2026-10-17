import CoreFoundation
import Foundation
import Testing

@main
struct TestHost {
    @MainActor
    static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["VELLUM_TEST_BUNDLE"],
              let bundle = Bundle(path: path) else {
            fatalError("VELLUM_TEST_BUNDLE must name a built test bundle")
        }
        try bundle.loadAndReturnError()
        var context = CFRunLoopSourceContext()
        let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)!
        CFRunLoopAddSource(CFRunLoopGetMain(), keepAlive, .defaultMode)
        Task { await Testing.__swiftPMEntryPoint() as Never }
        // AppKit may stop one loop iteration while Swift Testing still has pending tests.
        while true { CFRunLoopRun() }
    }
}

import Foundation

@MainActor
public final class OpenURLRelay {
    public static let shared = OpenURLRelay()

    private let currentTime: () -> TimeInterval
    private var handler: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []
    private var recentDeliveries: [URL: TimeInterval] = [:]

    init(currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }) {
        self.currentTime = currentTime
    }

    func activate(_ handler: @escaping ([URL]) -> Void) {
        self.handler = handler

        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        handler(urls)
    }

    public func open(_ urls: [URL]) {
        let fileURLs = uniqueFreshFileURLs(urls)
        guard !fileURLs.isEmpty else { return }

        if let handler {
            handler(fileURLs)
        } else {
            pendingURLs.append(contentsOf: fileURLs)
        }
    }

    private func uniqueFreshFileURLs(_ urls: [URL]) -> [URL] {
        let now = currentTime()
        recentDeliveries = recentDeliveries.filter { now - $0.value < 1.0 }

        var seen = Set<URL>()
        return urls.compactMap { url in
            guard url.isFileURL else { return nil }

            let normalizedURL = url.standardizedFileURL
            guard seen.insert(normalizedURL).inserted else { return nil }

            if let lastDelivery = recentDeliveries[normalizedURL], now - lastDelivery < 0.5 {
                return nil
            }

            recentDeliveries[normalizedURL] = now
            return normalizedURL
        }
    }
}

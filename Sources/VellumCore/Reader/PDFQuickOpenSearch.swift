import Combine
import Darwin
import Foundation

enum PDFQuickOpenFailure: Error, Equatable {
    case fzfMissing
    case indexUnavailable
    case matchingFailed(String)
}

@MainActor
final class PDFQuickOpenSearch: ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue { refreshResults() }
        }
    }
    @Published private(set) var results: [URL] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isSearching = false
    @Published private(set) var failure: PDFQuickOpenFailure?

    private let executableURL: URL?
    private var snapshot = PDFQuickOpenSnapshot(paths: [])
    private var index: PDFQuickOpenFileIndex?
    private var hasStartedIndexing = false
    private var isActive = false
    private var generation = 0
    private var matchingTask: Task<Void, Never>?
    private var matchingProcess: PDFQuickOpenMatchProcess?

    init(executableURL: URL? = PDFQuickOpenMatchProcess.findExecutable(), initialPaths: [URL]? = nil) {
        self.executableURL = executableURL
        if let initialPaths {
            snapshot = PDFQuickOpenSnapshot(paths: initialPaths)
            isLoading = false
            hasStartedIndexing = true
        }
    }

    deinit {
        index?.stop()
        matchingTask?.cancel()
        matchingProcess?.cancel()
    }

    func startIndexing() {
        guard !hasStartedIndexing else { return }
        hasStartedIndexing = true
        let index = PDFQuickOpenFileIndex { [weak self] snapshot, isGathering in
            guard let self else { return }
            self.isLoading = isGathering
            guard let snapshot else {
                self.failure = .indexUnavailable
                return
            }
            self.snapshot = snapshot
            if self.failure == .indexUnavailable { self.failure = nil }
            self.refreshResults()
        }
        self.index = index
        index.start()
    }

    func beginSearching() {
        isActive = false
        query = ""
        isActive = true
        startIndexing()
        refreshResults()
    }

    func endSearching() {
        isActive = false
        cancelMatching()
        results = []
    }

    private func cancelMatching() {
        generation &+= 1
        matchingTask?.cancel()
        matchingProcess?.cancel()
        matchingTask = nil
        matchingProcess = nil
        isSearching = false
    }

    private func refreshResults() {
        guard isActive else { return }
        cancelMatching()
        guard let executableURL else {
            failure = .fzfMissing
            results = []
            return
        }
        if case .matchingFailed = failure { failure = nil }
        guard !query.isEmpty else {
            results = snapshot.paths
            return
        }
        results = []
        guard !snapshot.paths.isEmpty else { return }
        isSearching = true
        let currentGeneration = generation
        let process = PDFQuickOpenMatchProcess(executableURL: executableURL, input: snapshot.input, query: query)
        matchingProcess = process
        matchingTask = Task { [weak self] in
            do {
                let results = try await process.run()
                guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }
                self.results = results
                if self.failure != .indexUnavailable { self.failure = nil }
                self.isSearching = false
                self.matchingProcess = nil
                self.matchingTask = nil
            } catch {
                guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }
                self.failure = error as? PDFQuickOpenFailure ?? .matchingFailed(error.localizedDescription)
                self.isSearching = false
                self.matchingProcess = nil
                self.matchingTask = nil
            }
        }
    }
}

private struct PDFQuickOpenSnapshot: Sendable {
    let paths: [URL]
    let input: Data

    init(paths: [URL]) {
        self.paths = paths.filter { url in
            guard url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else { return false }
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        }
        input = self.paths.reduce(into: Data()) { data, url in
            data.append(contentsOf: url.path.utf8)
            data.append(0)
        }
    }
}

// Query state belongs to its serial queue; only immutable snapshots reach the main actor.
private final class PDFQuickOpenFileIndex: @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let queue = OperationQueue()
    private let onChange: @MainActor @Sendable (PDFQuickOpenSnapshot?, Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var publishedFirstBatch = false
    private var isGathering = true
    private var stopped = false

    init(onChange: @escaping @MainActor @Sendable (PDFQuickOpenSnapshot?, Bool) -> Void) {
        self.onChange = onChange
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        queue.name = "Vellum PDF quick-open index"
    }

    func start() {
        queue.addOperation { [self] in
            guard !stopped else { return }
            query.operationQueue = queue
            query.predicate = NSPredicate(format: "kMDItemFSName LIKE[cd] %@", "*.pdf")
            query.searchScopes = [FileManager.default.homeDirectoryForCurrentUser]
            query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
            observers = [Notification.Name.NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate].map { name in
                NotificationCenter.default.addObserver(forName: name, object: query, queue: queue) { [weak self] _ in
                    self?.receive(name)
                }
            }
            if !query.start() {
                DispatchQueue.main.async { [onChange] in onChange(nil, false) }
            }
        }
    }

    func stop() {
        queue.addOperation { [self] in
            stopped = true
            query.stop()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }
    }

    private func receive(_ name: Notification.Name) {
        guard !stopped else { return }
        if name == .NSMetadataQueryGatheringProgress {
            guard !publishedFirstBatch, query.resultCount > 0 else { return }
            publishedFirstBatch = true
        } else if name == .NSMetadataQueryDidFinishGathering {
            isGathering = false
        }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let paths = (0..<query.resultCount).compactMap { index -> URL? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path)
        }
        let snapshot = PDFQuickOpenSnapshot(paths: paths)
        let isGathering = isGathering
        DispatchQueue.main.async { [onChange] in onChange(snapshot, isGathering) }
    }
}

// The lock protects cancellation against process launch; pipe I/O uses independent workers.
final class PDFQuickOpenMatchProcess: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let termination: AsyncStream<Int32>
    private let lock = NSLock()
    private var cancelled = false
    private let input: Data

    init(executableURL: URL, input: Data, query: String) {
        self.input = input
        let (termination, continuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.termination = termination
        process.terminationHandler = { process in
            continuation.yield(process.terminationStatus)
            continuation.finish()
        }
        process.executableURL = executableURL
        process.arguments = ["--read0", "--print0", "--scheme=path", "--filter=\(query)"]
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("FZF_DEFAULT_") }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Cancelling fzf can close its input while a worker is still writing.
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    static func findExecutable() -> URL? {
        let directories = ["/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return directories.lazy.filter { $0.hasPrefix("/") }.map {
            URL(fileURLWithPath: $0).appendingPathComponent("fzf")
        }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func run() async throws -> [URL] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    do {
                        try lock.withLock {
                            guard !cancelled else { throw CancellationError() }
                            guard let executableURL = process.executableURL,
                                  FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                                throw PDFQuickOpenFailure.fzfMissing
                            }
                            try process.run()
                        }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            async let output = Self.read(stdoutPipe.fileHandleForReading)
            async let diagnostics = Self.read(stderrPipe.fileHandleForReading)
            async let writeFailure = Self.write(input, to: stdinPipe.fileHandleForWriting)
            // waitUntilExit can miss a short-lived child's wakeup on a reused worker RunLoop.
            var exits = termination.makeAsyncIterator()
            let status = await exits.next()
            let (data, errorData, inputError) = try await (output, diagnostics, writeFailure)
            try Task.checkCancellation()
            guard let status else { throw CancellationError() }
            if status == 1 { return [] }
            guard status == 0 else {
                let detail = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw PDFQuickOpenFailure.matchingFailed(detail.isEmpty ? "fzf exited with status \(status)" : detail)
            }
            if let inputError { throw inputError }
            return try data.split(separator: 0).map { bytes in
                guard let path = String(bytes: bytes, encoding: .utf8), path.hasPrefix("/") else {
                    throw PDFQuickOpenFailure.matchingFailed("fzf returned an invalid file path")
                }
                return URL(fileURLWithPath: path)
            }
        } onCancel: {
            cancel()
        }
    }

    private static func read(_ handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    defer { try? handle.close() }
                    continuation.resume(returning: try handle.readToEnd() ?? Data())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func write(_ data: Data, to handle: FileHandle) async -> (any Error)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? handle.close() }
                do {
                    try handle.write(contentsOf: data)
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: error)
                }
            }
        }
    }
}

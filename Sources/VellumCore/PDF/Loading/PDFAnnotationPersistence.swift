@preconcurrency import PDFKit
import Foundation
import ObjectiveC

final class PDFAnnotationPersistence: @unchecked Sendable {
    enum SaveError: Error, Equatable, Sendable {
        case fileChanged
        case unreadable
        case writeFailed(String)

        var message: String {
            let language = AppUILanguage.saved()
            switch self {
            case .fileChanged:
                return language.text(.annotationSaveConflict)
            case .unreadable:
                return language.text(.annotationSaveUnreadable)
            case .writeFailed(let detail):
                return language.text(.annotationSaveWriteFailed) + (detail.isEmpty ? "" : "\n\n" + detail)
            }
        }
    }

    private struct FileSignature: Equatable {
        let size: UInt64
        let modifiedAt: Date
        let fileNumber: UInt64
        let volumeNumber: UInt64

        init(url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  let modifiedAt = attributes[.modificationDate] as? Date,
                  let fileNumber = attributes[.systemFileNumber] as? NSNumber,
                  let volumeNumber = attributes[.systemNumber] as? NSNumber else {
                throw SaveError.unreadable
            }
            self.size = size.uint64Value
            self.modifiedAt = modifiedAt
            self.fileNumber = fileNumber.uint64Value
            self.volumeNumber = volumeNumber.uint64Value
        }
    }

    // Independent PDFKit copies belong only to the serial writer after capture.
    private struct Snapshot: @unchecked Sendable {
        let highlights: [[PDFAnnotation]]
        let unlockedDocument: PDFDocument?

        @MainActor
        init(document: PDFDocument) throws {
            // ponytail: Vellum edits highlights only; expand this snapshot when another annotation editor is added.
            highlights = try (0..<document.pageCount).map { index in
                guard let page = document.page(at: index) else { throw SaveError.unreadable }
                return try page.annotations.filter { $0.type == "Highlight" }.map { annotation in
                    guard let copy = annotation.copy() as? PDFAnnotation else { throw SaveError.unreadable }
                    return copy
                }
            }
            if document.isEncrypted {
                let popups = try (0..<document.pageCount).map { index in
                    guard let page = document.page(at: index) else { throw SaveError.unreadable }
                    return PDFPopupSnapshot.capture(from: page)
                }
                guard !document.isLocked,
                      let copy = document.copy() as? PDFDocument,
                      !copy.isLocked else { throw SaveError.unreadable }
                for (index, snapshots) in popups.enumerated() {
                    guard let page = copy.page(at: index),
                          PDFPopupSnapshot.restore(snapshots, to: page) else { throw SaveError.unreadable }
                }
                unlockedDocument = copy
            } else {
                unlockedDocument = nil
            }
        }
    }

    private nonisolated(unsafe) static var associatedKey: UInt8 = 0

    static func register(_ document: PDFDocument, state: PDFAnnotationPersistence) {
        objc_setAssociatedObject(
            document,
            &associatedKey,
            state,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func existing(for document: PDFDocument) -> PDFAnnotationPersistence? {
        objc_getAssociatedObject(document, &associatedKey) as? PDFAnnotationPersistence
    }

    static func state(for document: PDFDocument) -> PDFAnnotationPersistence? {
        if let existing = existing(for: document) { return existing }
        guard let url = document.documentURL else { return nil }
        register(document, state: PDFAnnotationPersistence(url: url))
        return existing(for: document)
    }

    private let url: URL
    private let queue = DispatchQueue(label: "Vellum.annotation-writer", qos: .utility)
    private let lock = NSLock()
    private var revision = 0
    private var savedRevision = 0
    private var copiedRevision = 0
    private var lastError: SaveError?
    @MainActor var onPrepareToClose: (@MainActor () -> Void)?
    @MainActor var isPresentingRecovery = false
    // Accessed only by queue.
    private var diskSignature: FileSignature?

    init(url: URL) {
        self.url = url.standardizedFileURL.resolvingSymlinksInPath()
        diskSignature = try? FileSignature(url: self.url)
    }

    var hasUnprotectedChanges: Bool {
        lock.withLock { revision > max(savedRevision, copiedRevision) }
    }

    var hasUnsavedChanges: Bool {
        lock.withLock { revision > savedRevision }
    }

    var failure: SaveError? {
        lock.withLock { lastError }
    }

    func hasFileChanged(at url: URL) -> Bool {
        queue.sync {
            guard let diskSignature else { return true }
            return url.standardizedFileURL.resolvingSymlinksInPath() != self.url
                || (try? FileSignature(url: self.url)) != diskSignature
        }
    }

    @MainActor
    func save(_ document: PDFDocument, onFailure: @escaping @MainActor @Sendable () -> Void) {
        let currentRevision = lock.withLock {
            revision += 1
            return revision
        }
        let snapshot: Snapshot
        do {
            snapshot = try Snapshot(document: document)
        } catch {
            queue.async { [self] in
                lock.withLock { lastError = .unreadable }
                if lock.withLock({ revision == currentRevision }) {
                    Task { @MainActor in onFailure() }
                }
            }
            return
        }
        queue.async { [self] in
            guard lock.withLock({ revision == currentRevision }) else { return }
            write(snapshot, revision: currentRevision)
            if lock.withLock({ lastError != nil && revision == currentRevision }) {
                Task { @MainActor in onFailure() }
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    @MainActor
    func retry(_ document: PDFDocument) {
        do {
            let snapshot = try Snapshot(document: document)
            let currentRevision = lock.withLock { revision }
            queue.sync { write(snapshot, revision: currentRevision) }
        } catch {
            flush()
            lock.withLock { lastError = .unreadable }
        }
    }

    @MainActor
    func saveCopy(_ document: PDFDocument, to destination: URL) throws {
        flush()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard destination != url else { throw SaveError.fileChanged }
        let currentRevision = lock.withLock { revision }
        let targetSignature = try? FileSignature(url: destination)
        _ = try Self.writeAtomically(document, to: destination) {
            guard (try? FileSignature(url: destination)) == targetSignature else { throw SaveError.fileChanged }
        }
        lock.withLock { copiedRevision = currentRevision }
    }

    private func write(_ snapshot: Snapshot, revision currentRevision: Int) {
        do {
            guard let diskSignature else { throw SaveError.unreadable }
            guard (try? FileSignature(url: url)) == diskSignature else { throw SaveError.fileChanged }
            let independentDocument: PDFDocument
            if let unlockedDocument = snapshot.unlockedDocument {
                independentDocument = unlockedDocument
            } else {
                guard let reopenedDocument = PDFDocument(url: url),
                      !reopenedDocument.isLocked else { throw SaveError.unreadable }
                independentDocument = reopenedDocument
            }
            guard independentDocument.pageCount == snapshot.highlights.count else { throw SaveError.unreadable }
            for (index, highlights) in snapshot.highlights.enumerated() {
                guard let page = independentDocument.page(at: index) else { throw SaveError.unreadable }
                for annotation in page.annotations where annotation.type == "Highlight" { page.removeAnnotation(annotation) }
                for annotation in highlights {
                    guard let copy = annotation.copy() as? PDFAnnotation else { throw SaveError.unreadable }
                    page.addAnnotation(copy)
                }
            }
            self.diskSignature = try Self.writeAtomically(independentDocument, to: url) {
                guard (try? FileSignature(url: self.url)) == diskSignature else { throw SaveError.fileChanged }
            }
            lock.withLock {
                savedRevision = currentRevision
                lastError = nil
            }
        } catch {
            lock.withLock { lastError = (error as? SaveError) ?? .writeFailed(error.localizedDescription) }
        }
    }

    private static func writeAtomically(
        _ document: PDFDocument,
        to destination: URL,
        validateDestination: () throws -> Void
    ) throws -> FileSignature {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path), !manager.isWritableFile(atPath: destination.path) {
            throw SaveError.writeFailed(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError).localizedDescription)
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".vellum-\(UUID().uuidString).pdf")
        defer { try? manager.removeItem(at: temporary) }
        guard document.write(to: temporary) else { throw SaveError.writeFailed("") }
        let writtenSignature = try FileSignature(url: temporary)
        try validateDestination()
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
        let committedSignature = try FileSignature(url: destination)
        guard committedSignature == writtenSignature else { throw SaveError.fileChanged }
        return committedSignature
    }
}

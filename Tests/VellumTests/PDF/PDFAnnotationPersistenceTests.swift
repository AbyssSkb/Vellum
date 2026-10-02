import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF annotation persistence")
@MainActor
struct PDFAnnotationPersistenceTests {
    @Test
    func serialSavesKeepLatestAnnotationAndMetadata() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let page = try #require(fixture.document.page(at: 0))
        let annotation = PDFAnnotation(bounds: NSRect(x: 20, y: 40, width: 80, height: 12), forType: .highlight, withProperties: nil)
        annotation.contents = AIExplanationAnnotation.encode("First explanation")
        annotation.userName = "Original author"
        HighlightAnnotationMetadata.setGroupID("highlight-group", for: annotation)
        page.addAnnotation(annotation)

        fixture.persistence.save(fixture.document) {}
        annotation.contents = AIExplanationAnnotation.encode("Latest explanation")
        fixture.persistence.save(fixture.document) {}
        fixture.persistence.flush()

        let saved = try #require(PDFDocument(url: fixture.url)?.page(at: 0)?.annotations.first)
        #expect(AIExplanationAnnotation.decode(saved.contents) == "Latest explanation")
        #expect(saved.userName == "Original author")
        #expect(HighlightAnnotationMetadata.groupID(for: saved) == "highlight-group")
        #expect(!fixture.persistence.hasUnsavedChanges)
        #expect(fixture.persistence.failure == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["original.pdf"])
    }

    @Test
    func externalReplacementIsNeverOverwritten() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        addHighlight(to: fixture.document, text: "Unsaved local note")
        let external = makeDocument()
        external.documentAttributes = [PDFDocumentAttribute.titleAttribute: "External version"]
        #expect(external.write(to: fixture.url))
        let externalData = try Data(contentsOf: fixture.url)

        fixture.persistence.save(fixture.document) {}
        fixture.persistence.flush()

        #expect(fixture.persistence.failure == .fileChanged)
        #expect(fixture.persistence.hasUnprotectedChanges)
        #expect(try Data(contentsOf: fixture.url) == externalData)
    }

    @Test
    func failedWriteKeepsOriginalAndRetrySavesPendingChanges() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let originalData = try Data(contentsOf: fixture.url)
        addHighlight(to: fixture.document, text: "Pending note")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fixture.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.url.path) }

        fixture.persistence.save(fixture.document) {}
        fixture.persistence.flush()

        #expect(fixture.persistence.failure != nil)
        #expect(fixture.persistence.hasUnprotectedChanges)
        #expect(try Data(contentsOf: fixture.url) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["original.pdf"])

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.url.path)
        fixture.persistence.retry(fixture.document)
        #expect(!fixture.persistence.hasUnsavedChanges)
        #expect(PDFDocument(url: fixture.url)?.page(at: 0)?.annotations.first?.contents == "Pending note")
    }

    @Test
    func recoveryCopyProtectsOnlyTheCopiedRevision() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        addHighlight(to: fixture.document, text: "Local note")
        let external = makeDocument()
        external.documentAttributes = [PDFDocumentAttribute.titleAttribute: "External version"]
        #expect(external.write(to: fixture.url))
        let externalData = try Data(contentsOf: fixture.url)
        fixture.persistence.save(fixture.document) {}
        fixture.persistence.flush()
        let copyURL = fixture.directory.appendingPathComponent("recovered.pdf")

        try fixture.persistence.saveCopy(fixture.document, to: copyURL)

        #expect(PDFDocument(url: copyURL)?.page(at: 0)?.annotations.first?.contents == "Local note")
        #expect(fixture.document.documentURL == fixture.url)
        #expect(try Data(contentsOf: fixture.url) == externalData)
        #expect(!fixture.persistence.hasUnprotectedChanges)
        #expect(fixture.persistence.hasUnsavedChanges)

        let appState = AppState()
        let tab = PDFTab(url: fixture.url, document: fixture.document)
        _ = appState.tabStore.openInNewTabs([tab])
        #expect(appState.canCloseTab(tab.id))

        addHighlight(to: fixture.document, text: "Another note")
        fixture.persistence.save(fixture.document) {}
        fixture.persistence.flush()
        #expect(fixture.persistence.hasUnprotectedChanges)
        #expect(fixture.persistence.failure == .fileChanged)
    }

    @Test(arguments: [false, true])
    func highlightSavesPreserveForeignAnnotationsAndDocumentSecurity(encrypted: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vellum-preserve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("annotations.pdf")
        try await Task.detached(priority: .utility) {
            let fixtureDocument = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            fixtureDocument.insert(page, at: 0)
            let originalHighlight = PDFAnnotation(bounds: NSRect(x: 20, y: 40, width: 80, height: 12), forType: .highlight, withProperties: nil)
            originalHighlight.contents = "Saved highlight"
            originalHighlight.userName = "Saved author"
            originalHighlight.color = .yellow
            page.addAnnotation(originalHighlight)
            let externalNote = PDFAnnotation(bounds: NSRect(x: 30, y: 80, width: 24, height: 24), forType: .text, withProperties: nil)
            externalNote.contents = "External note"
            externalNote.userName = "External author"
            externalNote.color = .magenta
            page.addAnnotation(externalNote)
            if let popup = externalNote.popup {
                popup.bounds = NSRect(x: 123, y: 234, width: 301, height: 201)
                popup.setBoolean(true, forAnnotationKey: .open)
                popup.color = .magenta
                externalNote.popup = popup
            }
            let secondNote = PDFAnnotation(bounds: NSRect(x: 150, y: 80, width: 24, height: 24), forType: .text, withProperties: nil)
            secondNote.contents = "Second external note"
            secondNote.userName = "Second external author"
            secondNote.color = .cyan
            page.addAnnotation(secondNote)
            if let popup = secondNote.popup {
                popup.bounds = NSRect(x: 173, y: 334, width: 211, height: 171)
                popup.setBoolean(false, forAnnotationKey: .open)
                popup.color = .cyan
                secondNote.popup = popup
            }
            let link = PDFAnnotation(bounds: NSRect(x: 30, y: 120, width: 100, height: 14), forType: .link, withProperties: nil)
            link.action = PDFActionURL(url: URL(string: "https://example.com/foreign")!)
            page.addAnnotation(link)
            let didWrite = encrypted
                ? fixtureDocument.write(to: url, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "reader"])
                : fixtureDocument.write(to: url)
            guard didWrite else { throw CocoaError(.fileWriteUnknown) }
        }.value
        let document = try #require(PDFDocumentLoader().tab(for: url)?.document)
        #expect(document.isEncrypted == encrypted)
        #expect(document.isLocked == encrypted)
        if encrypted { #expect(document.unlock(withPassword: "reader")) }
        let originalPermissions = document.accessPermissions
        let foreignAnnotations = foreignAnnotationState(document)
        #expect(foreignAnnotations.map(\.type) == ["Text", "Popup", "Text", "Popup", "Link"])
        let sourcePopups = try #require(document.page(at: 0)?.annotations.filter { $0.type == "Popup" })
        #expect(sourcePopups.count == 2)
        #expect(HighlightGeometry.colorsMatch(sourcePopups[0].color, .magenta))
        #expect(HighlightGeometry.colorsMatch(sourcePopups[1].color, .cyan))
        let persistence = try #require(PDFAnnotationPersistence.existing(for: document))
        let editedHighlight = try #require(document.page(at: 0)?.annotations.first(where: { $0.type == "Highlight" }))
        editedHighlight.userName = "Current author"
        editedHighlight.color = .cyan
        addHighlight(to: document, text: "Added highlight")

        for text in ["Current highlight", "Latest highlight"] {
            editedHighlight.contents = text
            persistence.save(document) {}
            await Task.detached(priority: .utility) { persistence.flush() }.value

            #expect(!persistence.hasUnsavedChanges)
            #expect(persistence.failure == nil)
            let reopened = try #require(PDFDocument(url: url))
            #expect(reopened.isEncrypted == encrypted)
            #expect(reopened.isLocked == encrypted)
            if encrypted { #expect(reopened.unlock(withPassword: "reader")) }
            #expect(reopened.accessPermissions == originalPermissions)
            #expect(foreignAnnotationState(reopened) == foreignAnnotations)
            let highlights = try #require(reopened.page(at: 0)?.annotations.filter { $0.type == "Highlight" })
            #expect(highlights.count == 2)
            let savedHighlight = try #require(highlights.first(where: { $0.contents == text }))
            #expect(savedHighlight.userName == "Current author")
            #expect(HighlightGeometry.colorsMatch(savedHighlight.color, .cyan))
            #expect(highlights.contains { $0.contents == "Added highlight" })
        }
    }

    @Test
    func terminationRechecksDocumentsEditedDuringAnotherRecovery() throws {
        let first = try makeFixture()
        let second = try makeFixture()
        defer {
            try? FileManager.default.removeItem(at: first.directory)
            try? FileManager.default.removeItem(at: second.directory)
        }
        let appState = AppState()
        let firstTab = PDFTab(url: first.url, document: first.document)
        let secondTab = PDFTab(url: second.url, document: second.document)
        _ = appState.tabStore.openInNewTabs([firstTab, secondTab])
        var firstChecks = 0

        let canTerminate = appState.prepareToTerminate { id in
            if id == firstTab.id {
                firstChecks += 1
                return firstChecks == 1
            }
            // A later tab's recovery modal can deliver an earlier document's AI completion.
            let external = makeDocument()
            external.documentAttributes = [PDFDocumentAttribute.titleAttribute: "External edit"]
            #expect(external.write(to: first.url))
            addHighlight(to: first.document, text: "Late AI result")
            first.persistence.save(first.document) {}
            return true
        }

        #expect(!canTerminate)
        #expect(firstChecks == 2)
        first.persistence.flush()
        #expect(first.persistence.hasUnprotectedChanges)
        #expect(first.persistence.failure == .fileChanged)
    }

    @Test
    func closingWaitsForPendingSuccessfulSave() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        addHighlight(to: fixture.document, text: "Saved before close")
        let appState = AppState()
        let tab = PDFTab(url: fixture.url, document: fixture.document)
        _ = appState.tabStore.openInNewTabs([tab])
        fixture.persistence.save(fixture.document) {}

        #expect(appState.canCloseTab(tab.id))
        #expect(PDFDocument(url: fixture.url)?.page(at: 0)?.annotations.first?.contents == "Saved before close")
        #expect(!fixture.persistence.hasUnsavedChanges)
    }

    private struct ForeignAnnotationState: Equatable {
        let type: String?
        let bounds: NSRect
        let contents: String?
        let author: String?
        let color: [CGFloat]?
        let popupIsOpen: Bool?
        let linkURL: URL?
    }

    private func foreignAnnotationState(_ document: PDFDocument) -> [ForeignAnnotationState] {
        document.page(at: 0)?.annotations.filter { $0.type != "Highlight" }.map { annotation in
            let color = annotation.color.usingColorSpace(.deviceRGB)
            return ForeignAnnotationState(
                type: annotation.type,
                bounds: annotation.bounds,
                contents: annotation.contents,
                author: annotation.userName,
                color: color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] },
                popupIsOpen: annotation.type == "Popup" ? (annotation.value(forAnnotationKey: .open) as? NSNumber)?.boolValue : nil,
                linkURL: (annotation.action as? PDFActionURL)?.url
            )
        } ?? []
    }

    private func makeFixture() throws -> (directory: URL, url: URL, document: PDFDocument, persistence: PDFAnnotationPersistence) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vellum-annotations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("original.pdf")
        #expect(makeDocument().write(to: url))
        let document = try #require(PDFDocumentLoader().tab(for: url)?.document)
        let persistence = try #require(PDFAnnotationPersistence.existing(for: document))
        return (directory, url, document, persistence)
    }

    private func makeDocument() -> PDFDocument {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)
        return document
    }

    private func addHighlight(to document: PDFDocument, text: String) {
        let note = PDFAnnotation(bounds: NSRect(x: 30, y: 60, width: 100, height: 14), forType: .highlight, withProperties: nil)
        note.contents = text
        document.page(at: 0)?.addAnnotation(note)
    }
}

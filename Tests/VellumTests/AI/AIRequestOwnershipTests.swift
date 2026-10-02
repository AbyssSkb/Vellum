@preconcurrency import AppKit
@preconcurrency import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@Suite("AI request ownership and annotation preservation")
@MainActor
struct AIRequestOwnershipTests {
    @Test
    func recoloringKeepsPerLineNotesAuthorsAndUnselectedGroupMembers() throws {
        let fixture = try Fixture()
        let first = fixture.highlight(for: fixture.first, contents: AIExplanationAnnotation.encode("first answer"), author: "First author")
        let second = fixture.highlight(for: fixture.second, contents: "External note", author: "External author")
        let third = fixture.highlight(for: fixture.third, contents: AIExplanationAnnotation.encode("third answer"), author: "Third author")
        let customKey = PDFAnnotationKey(rawValue: "ExternalMetadata")
        second.setValue("keep me", forAnnotationKey: customKey)
        let selection = try #require(fixture.first.copy() as? PDFSelection)
        selection.add(fixture.second)

        let recolored = fixture.view.addHighlightAnnotations(for: selection, color: .cyan)

        #expect(recolored.contains { $0 === first })
        #expect(recolored.contains { $0 === second })
        #expect(fixture.page.annotations.contains { $0 === third })
        #expect(first.contents == AIExplanationAnnotation.encode("first answer"))
        #expect(first.userName == "First author")
        #expect(second.contents == "External note")
        #expect(second.userName == "External author")
        #expect(second.value(forAnnotationKey: customKey) as? String == "keep me")
        #expect(HighlightGeometry.colorsMatch(first.color, .cyan))
        #expect(HighlightGeometry.colorsMatch(second.color, .cyan))
        #expect(HighlightGeometry.colorsMatch(third.color, .yellow))
    }

    @Test
    func failedExplanationCannotReplaceSavedAnswerWhenHighlighting() throws {
        let fixture = try Fixture()
        let annotation = fixture.highlight(for: fixture.first, contents: AIExplanationAnnotation.encode("saved answer"), author: "Saved author")
        let model = AIExplanationPopoverModel(title: "Failed", text: "request error")
        model.requestStatus = .failed
        fixture.view.aiInteraction.activeExplanationModel = model
        fixture.view.aiInteraction.activeSelection = fixture.first

        fixture.view.highlightActiveAISelection()

        #expect(annotation.contents == AIExplanationAnnotation.encode("saved answer"))
        #expect(annotation.userName == "Saved author")
        #expect(fixture.page.annotations.contains { $0 === annotation })
    }

    @Test
    func replacedExplanationIgnoresLateChunksSuccessAndCleanup() async throws {
        let fixture = try Fixture()
        let window = fixture.attachWindow()
        defer { fixture.view.hideAIExplanationPopover(); window.close() }
        let firstAnnotation = fixture.highlight(for: fixture.first, contents: "first note", author: "First")
        let secondAnnotation = fixture.highlight(for: fixture.second, contents: "second note", author: "Second")
        let firstClient = ControlledAIClient()
        let secondClient = ControlledAIClient()
        let configuration = try Self.configuration()

        fixture.view.startAIExplanation(for: fixture.first, context: Self.context(), configuration: configuration, annotations: [firstAnnotation], using: firstClient)
        try await firstClient.waitUntilStarted()
        let firstTask = try #require(fixture.view.aiInteraction.explanationTask)
        let firstModel = try #require(fixture.view.aiInteraction.activeExplanationModel)
        fixture.view.startAIExplanation(for: fixture.second, context: Self.context(), configuration: configuration, annotations: [secondAnnotation], using: secondClient)
        try await secondClient.waitUntilStarted()
        let secondTask = try #require(fixture.view.aiInteraction.explanationTask)
        let secondID = fixture.view.aiInteraction.explanationRequestID
        let secondModel = try #require(fixture.view.aiInteraction.activeExplanationModel)

        firstClient.emit("late chunk")
        firstClient.complete(.success("late answer"))
        await firstTask.value
        #expect(firstModel.text.isEmpty)
        #expect(firstAnnotation.contents == "first note")
        #expect(secondAnnotation.contents == "second note")
        #expect(fixture.view.aiInteraction.explanationRequestID == secondID)
        #expect(fixture.view.aiInteraction.explanationTask != nil)

        // Shared selection state can change without changing this request's immutable target.
        fixture.view.aiInteraction.activeSelection = fixture.first
        secondClient.emit("new chunk")
        secondClient.complete(.success("new answer"))
        await secondTask.value
        #expect(secondModel.requestStatus == .completed)
        #expect(firstAnnotation.contents == "first note")
        #expect(secondAnnotation.contents == AIExplanationAnnotation.encode("new answer"))
        #expect(fixture.view.aiInteraction.explanationTask == nil)
    }

    @Test
    func replacedConversationIgnoresLateFailureAndKeepsItsMessageTarget() async throws {
        let fixture = try Fixture()
        let window = fixture.attachWindow()
        defer { fixture.view.hideAIExplanationPopover(); window.close() }
        let firstModel = AIConversationPopoverModel(context: Self.context())
        let secondModel = AIConversationPopoverModel(context: Self.context())
        let firstClient = ControlledAIClient()
        let secondClient = ControlledAIClient()
        let configuration = try Self.configuration()
        fixture.view.showAIConversationPopover(model: firstModel, at: nil)
        fixture.view.startAIConversationMessage("old question", model: firstModel, configuration: configuration, using: firstClient)
        try await firstClient.waitUntilStarted()
        let firstTask = try #require(fixture.view.aiInteraction.conversationTask)
        fixture.view.showAIConversationPopover(model: secondModel, at: nil)
        fixture.view.startAIConversationMessage("new question", model: secondModel, configuration: configuration, using: secondClient)
        try await secondClient.waitUntilStarted()
        let secondTask = try #require(fixture.view.aiInteraction.conversationTask)
        let secondID = fixture.view.aiInteraction.conversationRequestID
        let assistantID = try #require(secondModel.messages.last?.id)

        firstClient.emit("late chunk")
        firstClient.complete(.failure(ControlledAIClient.Failure.synthetic))
        await firstTask.value
        #expect(firstModel.messages.last?.content.isEmpty == true)
        #expect(secondModel.isSending)
        #expect(secondModel.errorMessage == nil)
        #expect(fixture.view.aiInteraction.conversationRequestID == secondID)
        #expect(fixture.view.aiInteraction.conversationTask != nil)

        secondModel.messages.append(AIConversationMessage(role: .assistant, content: "another message"))
        secondClient.emit("new chunk")
        secondClient.complete(.success("new answer"))
        await secondTask.value
        #expect(secondModel.messages.first { $0.id == assistantID }?.content == "new answer")
        #expect(secondModel.messages.last?.content == "another message")
        #expect(secondModel.requestStatus == .completed)
        #expect(fixture.view.aiInteraction.conversationTask == nil)
    }

    @Test(arguments: [false, true])
    func closingInactiveTabCancelsRequestBeforeDeferredDismantle(conversation: Bool) async throws {
        let fixture = try Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let closingURL = directory.appendingPathComponent("closing.pdf")
        let otherURL = directory.appendingPathComponent("other.pdf")
        let source = try #require(fixture.view.document)
        try #require(source.write(to: closingURL))
        try #require(source.write(to: otherURL))
        let suiteName = "Vellum.CloseAIRequest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false,
            notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
        ))
        appState.openInNewTabs(urls: [closingURL, otherURL])
        let closingTab = try #require(appState.tabs.first { $0.url == closingURL })
        let document = try #require(closingTab.document)
        let persistence = try #require(PDFAnnotationPersistence.existing(for: document))
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string) as NSString
        let selection = try #require(page.selection(for: text.range(of: "first line")))
        let bounds = try #require(HighlightGeometry.tightBounds(for: selection, on: page))
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.contents = "Original note"
        page.addAnnotation(annotation)
        persistence.save(document) {}
        persistence.flush()
        try #require(!persistence.hasUnsavedChanges)
        let originalData = try Data(contentsOf: closingURL)

        let window = fixture.attachWindow()
        defer { window.close() }
        let hostingView = NSHostingView(rootView: PDFReader(
            tabID: closingTab.id, document: document, snapshot: nil, isActive: false
        ).environmentObject(appState))
        hostingView.frame = window.contentView!.bounds
        window.contentView = hostingView
        @MainActor func reader(in view: NSView) -> VellumPDFView? {
            (view as? VellumPDFView) ?? view.subviews.lazy.compactMap { reader(in: $0) }.first
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while reader(in: hostingView) == nil, ContinuousClock.now < deadline {
            hostingView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1))
        }
        let mountedReader = try #require(reader(in: hostingView))
        try #require(persistence.onPrepareToClose != nil)
        try #require(appState.selectedTabID != closingTab.id)
        let client = ControlledAIClient()
        if conversation {
            let model = AIConversationPopoverModel(context: Self.context())
            mountedReader.showAIConversationPopover(model: model, at: nil)
            mountedReader.startAIConversationMessage("Question", model: model, configuration: try Self.configuration(), using: client)
        } else {
            mountedReader.startAIExplanation(for: selection, context: Self.context(), configuration: try Self.configuration(), annotations: [annotation], using: client)
        }
        try await client.waitUntilStarted()
        let task = try #require(conversation
            ? mountedReader.aiInteraction.conversationTask : mountedReader.aiInteraction.explanationTask)
        let explanations = appState.aiExplanationHistory.map(\.id)
        let conversations = appState.aiConversationHistory.map(\.updatedAt)

        appState.closeTab(closingTab.id)

        #expect(!appState.tabs.contains { $0.id == closingTab.id })
        #expect(mountedReader.superview != nil)
        #expect(mountedReader.aiInteraction.explanationRequestID == nil)
        #expect(mountedReader.aiInteraction.conversationRequestID == nil)
        #expect(mountedReader.aiInteraction.explanationTask == nil)
        #expect(mountedReader.aiInteraction.conversationTask == nil)
        client.emit("Late chunk")
        client.complete(.success("Late answer"))
        await task.value
        persistence.flush()
        #expect(annotation.contents == "Original note")
        #expect(!persistence.hasUnsavedChanges)
        #expect(persistence.failure == nil)
        #expect(try Data(contentsOf: closingURL) == originalData)
        #expect(appState.aiExplanationHistory.map(\.id) == explanations)
        #expect(appState.aiConversationHistory.map(\.updatedAt) == conversations)
    }

    private static func configuration() throws -> AIConfiguration {
        try AIConfiguration(baseURLString: "https://synthetic.invalid/v1", model: "synthetic", apiKey: "synthetic")
    }

    private static func context() -> AIExplanationContext {
        AIExplanationContext(selectedText: "selected", currentParagraph: nil, nearbyText: "nearby", fileName: "synthetic.pdf", directoryName: nil, outlineTitle: nil, pageNumbers: [1])
    }

    private struct Fixture {
        let view: VellumPDFView
        let page: PDFPage
        let first: PDFSelection
        let second: PDFSelection
        let third: PDFSelection

        @MainActor
        init() throws {
            _ = NSApplication.shared
            let data = NSMutableData()
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (index, text) in ["first line", "second line", "third line"].enumerated() {
                (text as NSString).draw(at: NSPoint(x: 72, y: 710 - index * 35), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
            context.closePDF()
            let document = try #require(PDFDocument(data: data as Data))
            page = try #require(document.page(at: 0))
            let text = try #require(page.string) as NSString
            first = try #require(page.selection(for: text.range(of: "first line")))
            second = try #require(page.selection(for: text.range(of: "second line")))
            third = try #require(page.selection(for: text.range(of: "third line")))
            view = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.document = document
        }

        @MainActor
        func highlight(for selection: PDFSelection, contents: String, author: String) -> PDFAnnotation {
            let bounds = HighlightGeometry.tightBounds(for: selection, on: page)!
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = .yellow
            annotation.quadrilateralPoints = HighlightGeometry.quadrilateralPoints(for: bounds)
            annotation.contents = contents
            annotation.userName = author
            HighlightAnnotationMetadata.setGroupID("shared group", for: annotation)
            page.addAnnotation(annotation)
            return annotation
        }

        @MainActor
        func attachWindow() -> NSWindow {
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            return window
        }
    }
}

@MainActor
private final class ControlledAIClient: AIExplaining {
    enum Failure: Error { case synthetic }
    private var continuation: CheckedContinuation<String, any Error>?
    private var onChunk: (@MainActor (String) -> Void)?

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while continuation == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        _ = try #require(continuation)
    }

    func emit(_ text: String) { onChunk?(text) }

    func complete(_ result: Result<String, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func streamExplanation(context: AIExplanationContext, configuration: AIConfiguration, onChunk: @escaping @MainActor (String) -> Void) async throws -> String {
        self.onChunk = onChunk
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func streamConversation(context: AIExplanationContext, messages: [AIConversationMessage], configuration: AIConfiguration, onChunk: @escaping @MainActor (String) -> Void) async throws -> String {
        try await streamExplanation(context: context, configuration: configuration, onChunk: onChunk)
    }

    func testConnection(configuration: AIConfiguration) async throws -> String { throw Failure.synthetic }
    func testFunction(configuration: AIConfiguration) async throws -> String { throw Failure.synthetic }
    func fetchModels(configuration: AIConfiguration) async throws -> [String] { throw Failure.synthetic }
    func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String { throw Failure.synthetic }
}

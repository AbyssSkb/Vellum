@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
    func vimHighlightSelection(color: NSColor) {
        let usedSearchSelection = currentSelection == nil
        guard let selection = currentSelection ?? searchController?.activeSearchSelection else {
            NSSound.beep()
            return
        }

        let annotations = addHighlightAnnotations(for: selection, color: color)
        guard !annotations.isEmpty else {
            NSSound.beep()
            return
        }

        if currentSelection != nil {
            clearSelection()
        }
        if usedSearchSelection {
            searchController?.hideMatchesAfterTextAction()
        }
        textSelectionNavigationState = nil
        needsDisplay = true
        persistAnnotationsIfPossible()
    }

    @discardableResult
    func addHighlightAnnotations(for selection: PDFSelection, color: NSColor) -> [PDFAnnotation] {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var annotations: [PDFAnnotation] = []
        var seen = Set<ObjectIdentifier>()
        let groupID = UUID().uuidString

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page) else { continue }

                let existing = highlightAnnotations(on: page, intersecting: [bounds])
                for annotation in existing {
                    annotation.color = color
                    if seen.insert(ObjectIdentifier(annotation)).inserted {
                        annotations.append(annotation)
                    }
                }

                // Keep existing annotation objects and their notes, authors, and custom metadata.
                let uncovered = HighlightGeometry.uncoveredRegions(
                    in: bounds,
                    coveredBy: existing.flatMap(HighlightGeometry.regions)
                )
                for region in uncovered {
                    let annotation = PDFAnnotation(bounds: region, forType: .highlight, withProperties: nil)
                    annotation.color = color
                    annotation.quadrilateralPoints = HighlightGeometry.quadrilateralPoints(for: region)
                    HighlightAnnotationMetadata.setGroupID(groupID, for: annotation)
                    annotation.shouldDisplay = true
                    annotation.shouldPrint = true
                    page.addAnnotation(annotation)
                    annotations.append(annotation)
                }
            }
        }

        return annotations
    }

    func vimDeleteHighlightsForSelection() -> Bool {
        let usedSearchSelection = currentSelection == nil
        guard let selection = currentSelection ?? searchController?.activeSearchSelection else { return false }

        let selectionsByPage = highlightSelectionBoundsByPage(for: selection)
        var didRemoveHighlight = false

        for pageSelection in selectionsByPage {
            didRemoveHighlight = removeHighlightAnnotations(
                on: pageSelection.page,
                intersecting: pageSelection.bounds
            ) || didRemoveHighlight
        }

        guard didRemoveHighlight else {
            NSSound.beep()
            return true
        }

        if currentSelection != nil {
            clearSelection()
        }
        if usedSearchSelection {
            searchController?.hideMatchesAfterTextAction()
        }
        needsDisplay = true
        persistAnnotationsIfPossible()
        return true
    }

    func vimExplainSelectedHighlight() {
        guard let selection = currentSelection ?? searchController?.activeSearchSelection,
              let selectedText = selection.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        let targetAnnotations = highlightedAnnotations(intersecting: selection)

        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current()
        } catch {
            showAIMessage(error.localizedDescription)
            NSSound.beep()
            return
        }

        guard let context = AIExplanationContextBuilder.context(
            for: selection,
            selectedText: selectedText,
            document: document
        ) else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        startAIExplanation(
            for: selection,
            context: context,
            configuration: configuration,
            annotations: targetAnnotations,
            using: AIExplanationClient.client(for: configuration)
        )
    }

    func startAIExplanation(
        for selection: PDFSelection,
        context: AIExplanationContext,
        configuration: AIConfiguration,
        annotations targetAnnotations: [PDFAnnotation],
        using client: any AIExplaining
    ) {
        aiInteraction.clearActiveRequest()
        let popoverModel = showStreamingAIExplanationPopover(
            title: context.selectedText.aiPopoverTitle,
            pronunciationSpeechText: context.selectedText,
            at: nil
        )
        aiInteraction.activeSelection = selection.copy() as? PDFSelection ?? selection
        let requestID = UUID()
        aiInteraction.explanationRequestID = requestID
        let requestDocument = document

        let task = Task { @MainActor [weak self] in
            do {
                let explanation = try await client.streamExplanation(
                    context: context,
                    configuration: configuration,
                    onChunk: { [weak self] chunk in
                        guard let self,
                              self.aiInteraction.explanationRequestID == requestID,
                              self.document === requestDocument else { return }
                        popoverModel?.append(chunk)
                    }
                )
                guard let self,
                      !Task.isCancelled,
                      self.aiInteraction.explanationRequestID == requestID,
                      self.document === requestDocument else { return }

                let attachedAnnotations = targetAnnotations.filter { annotation in
                    annotation.page?.document === requestDocument
                        && annotation.page?.annotations.contains(where: { $0 === annotation }) == true
                }
                for annotation in attachedAnnotations {
                    annotation.contents = AIExplanationAnnotation.encode(explanation)
                    annotation.userName = "Vellum AI"
                    annotation.modificationDate = Date()
                }

                if !attachedAnnotations.isEmpty {
                    self.needsDisplay = true
                    self.persistAnnotationsIfPossible()
                }
                self.appState?.upsertAIExplanationHistory(
                    AIExplanationHistoryItem(
                        id: UUID(),
                        selectedText: context.selectedText,
                        explanation: explanation,
                        fileName: context.fileName,
                        documentKey: context.documentKey,
                        pageNumbers: context.pageNumbers,
                        updatedAt: Date()
                    )
                )
                popoverModel?.isStreaming = false
                popoverModel?.requestStatus = .completed
                self.aiInteraction.explanationRequestID = nil
                self.aiInteraction.explanationTask = nil
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.aiInteraction.explanationRequestID == requestID,
                      self.document === requestDocument else { return }
                self.aiInteraction.explanationRequestID = nil
                self.aiInteraction.explanationTask = nil
                popoverModel?.isStreaming = false
                popoverModel?.requestStatus = .failed
                popoverModel?.title = AppUILanguage.saved().text(.aiExplanationFailed)
                popoverModel?.text = error.localizedDescription
                NSSound.beep()
            }
        }
        aiInteraction.explanationTask = task
    }

    func vimStartAIConversation() {
        guard let selection = currentSelection ?? searchController?.activeSearchSelection,
              let selectedText = selection.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        guard let context = AIExplanationContextBuilder.context(
            for: selection,
            selectedText: selectedText,
            document: document
        ) else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        let model = AIConversationPopoverModel(context: context)
        showAIConversationPopover(model: model, at: nil)
        aiInteraction.activeSelection = selection.copy() as? PDFSelection ?? selection
    }

    @discardableResult
    func sendAIConversationMessage(_ prompt: String, model: AIConversationPopoverModel?) -> Bool {
        guard let model,
              aiInteraction.activeConversationModel === model,
              !model.isSending else { return false }

        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return false }

        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current(profile: .conversation)
        } catch {
            model.errorMessage = error.localizedDescription
            model.requestStatus = .failed
            NSSound.beep()
            return false
        }

        startAIConversationMessage(
            question,
            model: model,
            configuration: configuration,
            using: AIExplanationClient.client(for: configuration)
        )
        return true
    }

    func startAIConversationMessage(
        _ question: String,
        model: AIConversationPopoverModel,
        configuration: AIConfiguration,
        using client: any AIExplaining
    ) {
        aiInteraction.cancelConversationRequest()
        let requestID = UUID()
        aiInteraction.conversationRequestID = requestID
        model.errorMessage = nil
        model.isSending = true
        model.requestStatus = .streaming
        let context = model.context
        model.messages.append(AIConversationMessage(role: .user, content: question))
        let assistantMessage = AIConversationMessage(role: .assistant, content: "")
        model.messages.append(assistantMessage)
        model.refreshPreferredHeight()
        appState?.upsertAIConversationHistory(model.historyItem)
        let messagesForRequest = Array(model.messages.dropLast())
        let assistantMessageID = assistantMessage.id

        let task = Task { @MainActor [weak self, weak model] in
            do {
                let answer = try await client.streamConversation(
                    context: context,
                    messages: messagesForRequest,
                    configuration: configuration,
                    onChunk: { chunk in
                        guard let self, let model,
                              self.aiInteraction.conversationRequestID == requestID,
                              self.aiInteraction.activeConversationModel === model,
                              let index = model.messages.firstIndex(where: { $0.id == assistantMessageID }) else { return }
                        model.messages[index].content += chunk
                        self.appState?.upsertAIConversationHistory(model.historyItem)
                    }
                )
                guard let self, let model,
                      !Task.isCancelled,
                      self.aiInteraction.conversationRequestID == requestID,
                      self.aiInteraction.activeConversationModel === model,
                      let index = model.messages.firstIndex(where: { $0.id == assistantMessageID }) else { return }
                model.messages[index].content = answer
                model.isSending = false
                model.requestStatus = .completed
                self.appState?.upsertAIConversationHistory(model.historyItem)
                self.aiInteraction.conversationRequestID = nil
                self.aiInteraction.conversationTask = nil
            } catch {
                guard let self, let model,
                      !Task.isCancelled,
                      self.aiInteraction.conversationRequestID == requestID,
                      self.aiInteraction.activeConversationModel === model else { return }
                if let index = model.messages.firstIndex(where: { $0.id == assistantMessageID }),
                   model.messages[index].content.isEmpty {
                    model.messages.remove(at: index)
                }
                model.errorMessage = error.localizedDescription
                model.isSending = false
                model.requestStatus = .failed
                model.refreshPreferredHeight()
                self.appState?.upsertAIConversationHistory(model.historyItem)
                self.aiInteraction.conversationRequestID = nil
                self.aiInteraction.conversationTask = nil
                NSSound.beep()
            }
        }
        aiInteraction.conversationTask = task
    }
}

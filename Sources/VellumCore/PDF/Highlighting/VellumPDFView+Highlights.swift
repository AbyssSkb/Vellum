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
        let groupID = UUID().uuidString

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page) else { continue }

                let preservedExplanation = existingAIExplanation(on: page, intersecting: [bounds])
                removeHighlightAnnotations(on: page, intersecting: bounds)

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                annotation.quadrilateralPoints = HighlightGeometry.quadrilateralPoints(for: bounds)
                HighlightAnnotationMetadata.setGroupID(groupID, for: annotation)
                if let preservedExplanation {
                    annotation.contents = AIExplanationAnnotation.encode(preservedExplanation)
                    annotation.userName = "Vellum AI"
                }
                annotation.shouldDisplay = true
                annotation.shouldPrint = true
                page.addAnnotation(annotation)
                annotations.append(annotation)
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

        let anchor = selectionPopoverRect(for: selection)
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

        aiInteraction.explanationTask?.cancel()
        aiInteraction.activeSelection = selection.copy() as? PDFSelection ?? selection
        aiInteraction.existingAnnotations = targetAnnotations
        let popoverModel = showStreamingAIExplanationPopover(
            title: selectedText.aiPopoverTitle,
            pronunciationSpeechText: selectedText,
            at: anchor
        )

        let task = Task { @MainActor [weak self] in
            do {
                let explanation = try await AIExplanationClient.streamExplanation(
                    context: context,
                    configuration: configuration,
                    onChunk: { chunk in
                        popoverModel?.append(chunk)
                    }
                )
                guard let self else { return }

                for annotation in self.aiInteraction.existingAnnotations {
                    annotation.contents = AIExplanationAnnotation.encode(explanation)
                    annotation.userName = "Vellum AI"
                    annotation.modificationDate = Date()
                }

                if !self.aiInteraction.existingAnnotations.isEmpty {
                    self.needsDisplay = true
                    self.persistAnnotationsIfPossible()
                }
                popoverModel?.isStreaming = false
                self.aiInteraction.explanationTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.aiInteraction.explanationTask = nil
                popoverModel?.isStreaming = false
                popoverModel?.title = "AI request failed"
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

        aiInteraction.conversationTask?.cancel()
        aiInteraction.activeSelection = selection.copy() as? PDFSelection ?? selection
        let model = AIConversationPopoverModel(context: context)
        showAIConversationPopover(model: model, at: selectionPopoverRect(for: selection))
    }

    func sendAIConversationMessage(_ prompt: String, model: AIConversationPopoverModel?) {
        guard let model,
              aiInteraction.activeConversationModel === model,
              !model.isSending else { return }

        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current(profile: .conversation)
        } catch {
            model.errorMessage = error.localizedDescription
            NSSound.beep()
            return
        }

        model.errorMessage = nil
        model.isSending = true
        let context = model.context
        model.messages.append(AIConversationMessage(role: .user, content: question))
        model.messages.append(AIConversationMessage(role: .assistant, content: ""))
        model.refreshPreferredHeight()
        appState?.upsertAIConversationHistory(model.historyItem)
        let messagesForRequest = Array(model.messages.dropLast())

        aiInteraction.conversationTask?.cancel()
        let task = Task { @MainActor [weak self, weak model] in
            do {
                let answer = try await AIExplanationClient.streamConversation(
                    context: context,
                    messages: messagesForRequest,
                    configuration: configuration,
                    onChunk: { chunk in
                        model?.appendToLatestAssistant(chunk)
                        if let model {
                            self?.appState?.upsertAIConversationHistory(model.historyItem)
                        }
                    }
                )
                guard let model else { return }
                model.replaceLatestAssistant(with: answer)
                model.isSending = false
                self?.appState?.upsertAIConversationHistory(model.historyItem)
                self?.aiInteraction.conversationTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard let model else { return }
                if let lastIndex = model.messages.indices.last,
                   model.messages[lastIndex].role == .assistant,
                   model.messages[lastIndex].content.isEmpty {
                    model.messages.remove(at: lastIndex)
                }
                model.errorMessage = error.localizedDescription
                model.isSending = false
                model.refreshPreferredHeight()
                self?.appState?.upsertAIConversationHistory(model.historyItem)
                self?.aiInteraction.conversationTask = nil
                NSSound.beep()
            }
        }
        aiInteraction.conversationTask = task
    }
}

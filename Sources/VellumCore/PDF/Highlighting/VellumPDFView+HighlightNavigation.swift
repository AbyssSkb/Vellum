@preconcurrency import AppKit
import PDFKit

@MainActor
struct HighlightListItem: Identifiable {
    let id = UUID()
    let annotations: [PDFAnnotation]
    let pageNumbers: [Int]
    let text: String

    var searchableText: String {
        ([text] + pageNumbers.map(String.init)).joined(separator: " ")
    }
}

extension VellumPDFView {
    func highlightListItems() -> [HighlightListItem] {
        guard let document else { return [] }
        var groups: [[PDFAnnotation]] = []
        var groupIndexes: [String: Int] = [:]
        var seen = Set<ObjectIdentifier>()

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.type == "Highlight" && annotation.shouldDisplay {
                guard seen.insert(ObjectIdentifier(annotation)).inserted else { continue }
                let group = highlightGroupAnnotations(for: annotation, on: page).filter(\.shouldDisplay)
                seen.formUnion(group.map(ObjectIdentifier.init))
                if let groupID = HighlightAnnotationMetadata.groupID(for: annotation) {
                    if let index = groupIndexes[groupID] {
                        groups[index].append(contentsOf: group)
                    } else {
                        groupIndexes[groupID] = groups.count
                        groups.append(group)
                    }
                } else {
                    groups.append(group)
                }
            }
        }

        return groups.map { annotations in
            let ordered = annotations.sorted { highlightPrecedes($0, $1, in: document) }
            let pageNumbers = Set(ordered.compactMap { $0.page }.map { document.index(for: $0) + 1 }).sorted()
            let text = selectionForHighlights(ordered)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return HighlightListItem(annotations: ordered, pageNumbers: pageNumbers, text: text)
        }.sorted {
            guard let lhs = $0.annotations.first, let rhs = $1.annotations.first else { return false }
            return highlightPrecedes(lhs, rhs, in: document)
        }
    }

    func vimSelectHighlight(_ item: HighlightListItem) {
        guard let document, let annotation = item.annotations.first, let page = annotation.page,
              item.annotations.allSatisfy({ annotation in
                  annotation.type == "Highlight" && annotation.shouldDisplay
                      && annotation.page?.document === document
                      && annotation.page?.annotations.contains(where: { $0 === annotation }) == true
              }) else { return }

        completePendingRestoreBeforeUserInteraction()
        cancelWordJump()
        hideAIExplanationPopover()
        searchController?.markReaderNavigated()
        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        textSelectionNavigationState = nil
        let selection = selectionForHighlights(item.annotations)
        let horizontalOrigin = horizontalOriginIfVisible(selection?.bounds(for: page) ?? annotation.bounds, on: page)
        setCurrentSelection(selection, animate: false)
        if let selection {
            go(to: selection)
        } else {
            go(to: annotation.bounds, on: page)
        }
        restoreHorizontalOrigin(horizontalOrigin)
        let generation = restoreGeneration
        highlightNavigationAnchor = (annotation, generation)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.document === document, self.restoreGeneration == generation,
                  annotation.page === page, page.annotations.contains(where: { $0 === annotation }) else { return }
            if let selection { self.go(to: selection) } else { self.go(to: annotation.bounds, on: page) }
            self.restoreHorizontalOrigin(horizontalOrigin)
            self.scheduleReadingPositionReport(userNavigated: true)
        }
        focus()
    }

    func vimNavigateHighlight(_ direction: Int) {
        let items = highlightListItems()
        guard !items.isEmpty, let document else {
            NSSound.beep()
            return
        }
        let selected = currentSelection.map(highlightedAnnotations(intersecting:)) ?? []
        let selectedIDs = Set(selected.map(ObjectIdentifier.init))
        let selectedIndexes = items.indices.filter { index in
            items[index].annotations.contains { selectedIDs.contains(ObjectIdentifier($0)) }
        }
        var currentIndex = direction > 0 ? selectedIndexes.last : selectedIndexes.first
        if currentIndex == nil, currentSelection == nil,
           let anchor = highlightNavigationAnchor, anchor.generation == restoreGeneration {
            currentIndex = items.firstIndex { $0.annotations.contains { $0 === anchor.annotation } }
        }
        let index: Int
        if let currentIndex {
            index = (currentIndex + (direction > 0 ? 1 : items.count - 1)) % items.count
        } else if let destination = readingDestination(), let page = destination.page {
            let pageIndex = document.index(for: page)
            let geometry = PDFPageDisplayGeometry(page: page, box: displayBox)
            let point = geometry.point(forPagePoint: destination.point)
            let afterPosition = items.indices.filter { index in
                guard let annotation = items[index].annotations.first, let targetPage = annotation.page else { return false }
                let targetIndex = document.index(for: targetPage)
                if targetIndex != pageIndex { return targetIndex > pageIndex }
                return geometry.rect(forPageRect: annotation.bounds).midY < point.y
            }
            if direction > 0 {
                index = afterPosition.first ?? 0
            } else {
                index = afterPosition.first.map { ($0 + items.count - 1) % items.count } ?? items.count - 1
            }
        } else {
            index = direction > 0 ? 0 : items.count - 1
        }
        vimSelectHighlight(items[index])
    }

    private func selectionForHighlights(_ annotations: [PDFAnnotation]) -> PDFSelection? {
        let selections = annotations.flatMap { annotation -> [PDFSelection] in
            guard let page = annotation.page else { return [] }
            return HighlightGeometry.regions(for: annotation).compactMap { bounds in
                guard let selection = page.selection(for: bounds),
                      selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
                return selection
            }
        }
        guard let selection = selections.first?.copy() as? PDFSelection else { return nil }
        for remaining in selections.dropFirst() { selection.add(remaining) }
        return selection
    }

    private func highlightPrecedes(_ lhs: PDFAnnotation, _ rhs: PDFAnnotation, in document: PDFDocument) -> Bool {
        guard let lhsPage = lhs.page, let rhsPage = rhs.page else { return false }
        let lhsIndex = document.index(for: lhsPage)
        let rhsIndex = document.index(for: rhsPage)
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        let geometry = PDFPageDisplayGeometry(page: lhsPage, box: displayBox)
        let lhsBounds = geometry.rect(forPageRect: HighlightGeometry.regions(for: lhs).first ?? lhs.bounds)
        let rhsBounds = geometry.rect(forPageRect: HighlightGeometry.regions(for: rhs).first ?? rhs.bounds)
        if lhsBounds.maxY != rhsBounds.maxY { return lhsBounds.maxY > rhsBounds.maxY }
        if lhsBounds.minX != rhsBounds.minX { return lhsBounds.minX < rhsBounds.minX }
        return (lhsPage.annotations.firstIndex { $0 === lhs } ?? 0)
            < (rhsPage.annotations.firstIndex { $0 === rhs } ?? 0)
    }
}

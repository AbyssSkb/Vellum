import Foundation

enum TextSelectionRangeBuilder {
    static func pageRanges(
        for line: VimTextLine,
        startSlot rawStartSlot: Int,
        endSlot rawEndSlot: Int,
        pageStart: Int
    ) -> [Range<Int>] {
        let startSlot = min(max(rawStartSlot, 0), line.characters.count)
        let endSlot = min(max(rawEndSlot, 0), line.characters.count)
        guard endSlot > startSlot else { return [] }

        let offsets = line.characters[startSlot..<endSlot]
            .map { $0.globalOffset - pageStart }
            .sorted()

        return contiguousRanges(from: offsets)
    }

    static func contiguousRanges(from sortedOffsets: [Int]) -> [Range<Int>] {
        guard var runStart = sortedOffsets.first else { return [] }

        var ranges: [Range<Int>] = []
        var previous = runStart

        for offset in sortedOffsets.dropFirst() {
            if offset == previous + 1 {
                previous = offset
                continue
            }

            ranges.append(runStart..<(previous + 1))
            runStart = offset
            previous = offset
        }

        ranges.append(runStart..<(previous + 1))
        return ranges
    }
}

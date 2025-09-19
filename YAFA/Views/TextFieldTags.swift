import SwiftUI

/// An horizontal list of tags kept in sync with a text field, notably to handle interaction with
/// "#".
struct TextFieldTags: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    let tags: [FlashcardTag]
    let selectedTags: [FlashcardTag]
    let onAdd: (FlashcardTag) -> Void
    let onRemove: (FlashcardTag) -> Void

    @State private var nonSelectedTags: [FlashcardTag] = []
    @State private var tagEntry: TagEntry? = nil

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                if text.last != "#" {
                    Button("#") {
                        if text.last?.isWhitespace == false {
                            text.append(" ")
                        }
                        text.append("#")
                    }
                }

                if let tagEntry, let newTagName = tagEntry.newTagName {
                    Button(newTagName, systemImage: "plus") {
                        onAdd(FlashcardTag(name: newTagName))
                        clearTagEntry()
                    }
                }

                ForEach(tagEntry?.selectedTags ?? selectedTags) { tag in
                    Button(tag.name) {
                        onRemove(tag)
                        clearTagEntry()
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(.background)
                }

                ForEach(tagEntry?.nonSelectedTags ?? nonSelectedTags) { tag in
                    Button(tag.name) {
                        onAdd(tag)
                        clearTagEntry()
                    }
                }
            }
            .glassEffectTransition(.identity)
        }
        .animation(.default, value: text)
        .animation(.default, value: tagEntry?.newTagName)
        .animation(.default, value: selectedTags)
        .animation(.default, value: nonSelectedTags)

        // The selection doesn't change when editing CJK characters like ㅎ -> 하, so we also
        // update suggested tags on text change.
        .onChange(of: text) { updateSearch(includingTagSelection: false) }
        .onChange(of: selection) { updateSearch(includingTagSelection: false) }
        .onChange(of: tags, initial: true) { updateSearch(includingTagSelection: true) }
        .onChange(of: selectedTags) { updateSearch(includingTagSelection: true) }
    }

    private func updateSearch(includingTagSelection: Bool) {
        if includingTagSelection {
            nonSelectedTags = tags.removing(subset: selectedTags)
        }

        tagEntry = .init(
            from: tagEntry,
            tags: tags,
            selectedTags: selectedTags,
            nonSelectedTags: nonSelectedTags,
            text: text,
            selection: selection
        )
    }

    private func clearTagEntry() {
        if let tagEntry {
            text.removeSubrange(tagEntry.range)
            // SwiftUI will crash due to `TextField(selection:)`, so reset it before
            // continuing: https://github.com/swiftlang/swift/issues/82359.
            selection = nil
        }
    }
}

private struct TagEntry {
    /// Range where the tag is being input, including "#".
    let range: Range<String.Index>
    /// Search dictionary used to find the tag being input.
    let search: SearchDictionary<FlashcardTag>
    let newTagName: String?
    var selectedTags: [FlashcardTag]
    var nonSelectedTags: [FlashcardTag]

    init?(
        from previous: TagEntry?,
        tags: [FlashcardTag],
        selectedTags: [FlashcardTag],
        nonSelectedTags: [FlashcardTag],
        text: String,
        selection: TextSelection?
    ) {
        // Get active selection.
        guard
            let rawSelectionStartIndex =
                switch selection?.indices {
                case .multiSelection(let rangeSet):
                    rangeSet.ranges.first?.lowerBound
                case .selection(let range):
                    range.lowerBound
                default:
                    nil
                },
            rawSelectionStartIndex <= text.endIndex
        else {
            return nil
        }

        // SwiftUI sometimes gives us an UTF-16 selection index for an UTF-8 string, which messes up
        // with the loop below.
        let selectionStartIndex = String.Index(rawSelectionStartIndex, within: text)!

        // Starting from the selection start, go back to find a '#', which represents the start of
        // the tag.
        var tagStartIndex = selectionStartIndex

        while true {
            guard tagStartIndex != text.startIndex else { return nil }

            tagStartIndex = text.index(before: tagStartIndex)

            let unicodeScalar = text.unicodeScalars[tagStartIndex]

            guard !unicodeScalar.properties.isWhitespace else { return nil }

            if unicodeScalar == tagStartUnicodeScalar {
                break
            }
        }

        let textStartIndex = text.index(after: tagStartIndex)

        self.range = tagStartIndex..<selectionStartIndex
        self.search = previous?.search ?? .init(tags, by: \.name)

        guard textStartIndex != selectionStartIndex else {
            // Our selection is just '#'; suggest all tags.
            self.selectedTags = selectedTags
            self.nonSelectedTags = nonSelectedTags
            self.newTagName = nil

            return
        }

        // We have a tag '#...'. Update suggested tags.
        let tagText = text[textStartIndex..<selectionStartIndex]
        let matchingTags = Set<FlashcardTag>(search.starting(with: tagText))

        self.selectedTags = selectedTags.filter { matchingTags.contains($0) }
        self.nonSelectedTags = nonSelectedTags.filter { matchingTags.contains($0) }

        guard let exactMatch = matchingTags.first(where: { $0.name.count == tagText.count }) else {
            // If there is no exact match, suggest creating a new tag.
            self.newTagName = String(tagText)

            return
        }

        // If there is an exact match, show it first.
        if let index = self.selectedTags.firstIndex(of: exactMatch) {
            self.selectedTags.move(fromOffsets: .init(integer: index), toOffset: 0)
        } else if let index = self.nonSelectedTags.firstIndex(of: exactMatch) {
            self.nonSelectedTags.move(fromOffsets: .init(integer: index), toOffset: 0)
        } else {
            assertionFailure()
        }
        self.newTagName = nil
    }
}

private let tagStartUnicodeScalar = "#".unicodeScalars.first!

extension Array where Element: Equatable & Hashable {
    fileprivate func removing(subset elements: Self) -> Self {
        if elements.isEmpty {
            return self
        }
        if elements.count == count {
            return []
        }
        if count < 20 && elements.count < 4 {
            return self.filter { !elements.contains($0) }
        }

        let set = Set(elements)

        return self.filter { !set.contains($0) }
    }
}

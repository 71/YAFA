import SwiftData
import SwiftUI

/// The front and back text fields in a `Flashcard`.
struct FlashcardTextFields: View {
    let flashcard: Flashcard
    let autoFocus: Bool

    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @FocusState private var focusedField: Bool?

    @State private var frontTextSelection: TextSelection?
    @State private var frontTextSuggestedNewTag: (String, Range<String.Index>)?
    @State private var frontTextSuggestedTags: [(tag: FlashcardTag, range: Range<String.Index>)]?

    var body: some View {
        TextField(
            "Front", text: bindToProperty(of: flashcard, \.front),
            selection: $frontTextSelection, axis: .vertical
        )
        .focused($focusedField, equals: true)
        .onAppear { if autoFocus { focusedField = true } }
        .onChange(of: frontTextSelection) { updateSuggestedTags() }
        // The selection doesn't change when editing CJK characters like ㅎ -> 하, so we also
        // update suggested tags here.
        .onChange(of: flashcard.front) { updateSuggestedTags() }

        if let frontTextSuggestedTags {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(frontTextSuggestedTags, id: \.0) { (tag, range) in
                        Button {
                            flashcard.add(tag: tag)
                            flashcard.front.removeSubrange(range)

                            // SwiftUI will crash due to `TextField(selection:)`, so reset it before
                            // continuing: https://github.com/swiftlang/swift/issues/82359.
                            frontTextSelection = nil
                        } label: {
                            if flashcard.has(tag: tag) {
                                Label(tag.name, systemImage: "checkmark")
                            } else {
                                Text(tag.name)
                            }
                        }
                    }

                    if let (text, range) = frontTextSuggestedNewTag {
                        Button(text, systemImage: "plus") {
                            flashcard.add(tag: .init(name: text))
                            flashcard.front.removeSubrange(range)

                            // SwiftUI will crash due to `TextField(selection:)`, so reset it before
                            // continuing: https://github.com/swiftlang/swift/issues/82359.
                            frontTextSelection = nil
                        }
                    }

                    Spacer()
                }
                .buttonStyle(.bordered)
            }
        }

        TextField("Back", text: bindToProperty(of: flashcard, \.back), axis: .vertical)
    }

    private func updateSuggestedTags() {
        frontTextSuggestedNewTag = nil
        frontTextSuggestedTags = nil

        // Get active selection.
        guard
            let frontTextSelection,
            let selectionStartIndex =
                switch frontTextSelection.indices {
                case .multiSelection(let rangeSet):
                    rangeSet.ranges.first?.lowerBound
                case .selection(let range):
                    range.lowerBound
                default:
                    nil
                }
        else { return }

        // Compute tag prefixes from active selection.
        let frontText = flashcard.front

        // Starting from the selection start, go back to find a '#', which represents the start of
        // the tag.
        var tagStartIndex = selectionStartIndex

        while true {
            guard tagStartIndex != frontText.startIndex else { return }

            tagStartIndex = frontText.index(before: tagStartIndex)

            let unicodeScalar = frontText.unicodeScalars[tagStartIndex]

            guard !unicodeScalar.properties.isWhitespace else { return }

            if unicodeScalar == tagStartUnicodeScalar {
                break
            }
        }

        let textStartIndex = frontText.index(after: tagStartIndex)

        guard textStartIndex != selectionStartIndex else {
            // Our selection is just '#'; suggest all tags.
            let range = tagStartIndex..<selectionStartIndex

            frontTextSuggestedTags = allTags.map { tag in (tag, range) }

            return
        }

        // We have a tag '#...'. Update suggested tags.
        let tagText = frontText[textStartIndex..<selectionStartIndex]
        let prefixText = tagText.localizedLowercase
        var hasExactMatch = false

        frontTextSuggestedTags = allTags.compactMap { tag in
            guard
                tag.name.count >= prefixText.count,
                tag.name.localizedLowercase.hasPrefix(prefixText)
            else { return nil }

            hasExactMatch = hasExactMatch || tag.name.count == tagText.count

            return (tag, tagStartIndex..<selectionStartIndex)
        }

        // If there is no exact match, suggest creating a new tag.
        if !hasExactMatch {
            frontTextSuggestedNewTag = (String(tagText), tagStartIndex..<selectionStartIndex)
        }
    }
}

private let tagStartUnicodeScalar = "#".unicodeScalars.first!

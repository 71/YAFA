import SwiftData
import SwiftUI

/// The front and back text fields in a `Flashcard`.
struct FlashcardTextFields: View {
    @Binding var focusedFlashcard: Flashcard?

    let flashcard: Flashcard
    let autoFocus: Bool
    let tags: [FlashcardTag]
    let tagsSearch: SearchDictionary<FlashcardTag>

    @FocusState private var focusedField: Bool?

    @State private var frontTextSelection: TextSelection?

    var body: some View {
        TextField(
            "Front",
            text: bindToProperty(of: flashcard, \.front),
            selection: $frontTextSelection,
            axis: .vertical
        )
        .focused($focusedField, equals: true)
        .onAppear { if autoFocus { focusedField = true } }

        .onChange(of: focusedField, initial: true) { old, new in
            if focusedField != nil {
                focusedFlashcard = flashcard
            } else if focusedFlashcard == flashcard {
                // Unfocus flashcard _we_ marked as focused.
                focusedFlashcard = nil
            }
        }

        if focusedField == true && (!tags.isEmpty || flashcard.front.contains("#")) {
            TextFieldTags(
                text: bindToProperty(of: flashcard, \.front),
                selection: $frontTextSelection,
                tags: tags,
                selectedTags: flashcard.tags ?? []
            ) { addedTag in
                flashcard.add(tag: addedTag)
            } onRemove: { removedTag in
                flashcard.remove(tag: removedTag)
            }
        }

        TextField("Back", text: bindToProperty(of: flashcard, \.back), axis: .vertical)
            .focused($focusedField, equals: false)
    }
}

private let tagStartUnicodeScalar = "#".unicodeScalars.first!

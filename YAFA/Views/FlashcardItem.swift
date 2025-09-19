import SwiftUI

struct FlashcardItem: View {
    @Binding var focusedFlashcard: Flashcard?

    let flashcard: Flashcard
    let tags: [FlashcardTag]
    let tagsSearch: SearchDictionary<FlashcardTag>

    var body: some View {
        VStack {
            FlashcardTextFields(
                focusedFlashcard: $focusedFlashcard,
                flashcard: flashcard,
                autoFocus: false,
                tags: tags,
                tagsSearch: tagsSearch
            )
        }
    }
}

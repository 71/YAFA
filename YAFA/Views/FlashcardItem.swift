import SwiftUI

struct FlashcardItem: View {
    let flashcard: Flashcard
    let allTagsSearch: SearchDictionary<FlashcardTag>

    var body: some View {
        VStack {
            FlashcardTextFields(flashcard: flashcard, autoFocus: false, allTagsSearch: allTagsSearch)
        }
    }
}

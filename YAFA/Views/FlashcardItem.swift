import SwiftUI

struct FlashcardItem: View {
    let flashcard: Flashcard
    let resetIfNew: (() -> Void)?

    @FocusState private var isFocused
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack {
            FlashcardTextFields(flashcard: flashcard, autoFocus: false)
        }
        .focused($isFocused)
        .onChange(of: flashcard.front) { manageSaveState() }
        .onChange(of: flashcard.back) { manageSaveState() }
        .onChange(of: flashcard.notes) { manageSaveState() }
        .onDisappear {
            if let resetIfNew, !flashcard.isEmpty {
                resetIfNew()
            }
        }
    }

    private func manageSaveState() {
        if resetIfNew != nil {
            flashcard.insertIfNonEmpty(to: modelContext)
        }
    }
}

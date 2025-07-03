import SwiftData
import SwiftUI

struct FlashcardItem: View {
    let flashcard: Flashcard
    let resetIfNew: (() -> Void)?

    @FocusState private var isFocused
    @Environment(\.modelContext) private var modelContext
    @Query private var allTags: [FlashcardTag]

    var body: some View {
        VStack {
            TextField("Front", text: bindToProperty(of: flashcard, \.front))
            TextField("Back", text: bindToProperty(of: flashcard, \.back))

            if isFocused {
                HStack {
                    Menu {
                        ForEach(allTags) { tag in
                            CheckboxButton(
                                text: tag.name,
                                checked: flashcard.has(tag: tag)
                            ) {
                                if $0 {
                                    flashcard.add(tag: tag)
                                } else {
                                    flashcard.remove(tag: tag)
                                }
                            }
                        }
                        .menuActionDismissBehavior(.disabled)

                        Divider()

                        NavigationLink {
                            FlashcardEditor(flashcard: flashcard, resetIfNew: resetIfNew)
                        } label: {
                            Label("New tag", systemImage: "plus")
                        }
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }

                    Spacer()
                }
                .font(.subheadline)
            }
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

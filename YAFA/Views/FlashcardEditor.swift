import SwiftData
import SwiftUI

struct FlashcardEditor: View {
    let flashcard: Flashcard
    let autoFocus: Bool

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @State private var allTagsSearch: SearchDictionary<FlashcardTag> = .init()

    @AppStorage("prefer_relative_date") private var relativeDate = false

    var body: some View {
        Form {
            Section(header: Text("Content")) {
                FlashcardTextFields(
                    focusedFlashcard: .constant(nil),
                    flashcard: flashcard,
                    autoFocus: autoFocus,
                    tags: allTags,
                    tagsSearch: allTagsSearch
                )
            }

            Section(header: Text("Tags")) {
                TagSelectionList(
                    selectedTags: flashcard.tags ?? [],
                    addTag: { flashcard.add(tag: $0) },
                    removeTags: { flashcard.remove(tagOffsets: $0) }
                )
            }

            Section(header: Text("Notes")) {
                TextField(
                    "Notes",
                    text: bindToProperty(of: flashcard, \.notes),
                    axis: .vertical
                )
            }

            if flashcard.modelContext != nil {
                Section(header: Text("Information")) {
                    LabeledContent {
                        DateText(
                            date: flashcard.creationDate,
                            relative: $relativeDate
                        )
                    } label: {
                        Text("Created")
                    }
                    LabeledContent {
                        DateText(
                            date: flashcard.modificationDate,
                            relative: $relativeDate
                        )
                    } label: {
                        Text("Modified")
                    }

                    DatePicker(
                        "Next due",
                        selection: Binding {
                            flashcard.nextReviewDate
                        } set: {
                            flashcard.nextReviewDate = $0
                        }
                    )
                }
                .monospacedDigit()
            }

            if let reviews = flashcard.reviews, !reviews.isEmpty {
                Section(header: Text("Review history")) {
                    ForEach(reviews.reversed()) { review in
                        let reviewImage =
                            switch review.outcome {
                            case .ok: "checkmark"
                            case .fail: "xmark"
                            }

                        HStack {
                            DateText(date: review.date, relative: $relativeDate)
                            Spacer()
                            Image(systemName: reviewImage)
                        }
                    }
                }
                .monospacedDigit()
            }
        }
        .navigationTitle("Flashcard")
        .toolbar {
            Button {
                flashcard.modelContext?.delete(flashcard)
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onChange(of: allTags, initial: true) {
            allTagsSearch = .init(allTags, by: \.name)
        }
    }
}

struct NewFlashcardEditor: View {
    let text: String
    let tags: [FlashcardTag]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var pendingFlashcard: Flashcard

    init(text: String, tags: [FlashcardTag]) {
        self.text = text
        self.tags = tags
        self.pendingFlashcard = .init(front: text, tags: tags)
    }

    var body: some View {
        let handleChange = {
            if pendingFlashcard.front.isEmpty && pendingFlashcard.back.isEmpty
                && pendingFlashcard.notes.isEmpty
            {
                modelContext.delete(pendingFlashcard)
            } else {
                modelContext.insert(pendingFlashcard)
            }
        }

        FlashcardEditor(
            flashcard: pendingFlashcard,
            autoFocus: true
        )
        .onChange(of: pendingFlashcard.front, initial: true, handleChange)
        .onChange(of: pendingFlashcard.back, handleChange)
        .onChange(of: pendingFlashcard.notes, handleChange)
    }
}

extension View {
    func saveIfNonEmpty(
        or: String,
        flashcard: Flashcard,
        withTags tags: [FlashcardTag],
        in modelContext: ModelContext
    ) -> some View {
        let handleChange = {
            if (flashcard.front.isEmpty || flashcard.front == or) && flashcard.back.isEmpty
                && flashcard.notes.isEmpty
            {
                modelContext.delete(flashcard)
            } else {
                flashcard.tags = tags
                modelContext.insert(flashcard)
            }
        }

        return
            self
            .onChange(of: flashcard.front, initial: true, handleChange)
            .onChange(of: flashcard.back, initial: false, handleChange)
            .onChange(of: flashcard.notes, initial: false, handleChange)
    }
}

private func reviewDateFormatter(relative: Bool) -> DateFormatter {
    let dateFormatter = DateFormatter()

    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .short
    dateFormatter.doesRelativeDateFormatting = relative

    return dateFormatter
}

private struct DateText: View {
    let date: Date
    @Binding var relative: Bool

    private static let dateFormatter = reviewDateFormatter(relative: false)
    private static let relativeDateFormatter = reviewDateFormatter(
        relative: true
    )

    var body: some View {
        Text(
            (relative ? Self.relativeDateFormatter : Self.dateFormatter)
                .string(from: date)
        )
        .onTapGesture {
            relative = !relative
        }
    }
}

#Preview {
    let container = previewModelContainer()
    let anyFlashcard = try! container.mainContext.fetch(
        FetchDescriptor<Flashcard>(
            predicate: Predicate.true,
            sortBy: []
        )
    ).first!

    NavigationStack {
        FlashcardEditor(flashcard: anyFlashcard, autoFocus: false)
    }
    .modelContainer(container)
}

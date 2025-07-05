import SwiftData
import SwiftUI

struct FlashcardEditor: View {
    let flashcard: Flashcard
    let autoFocus: Bool
    let resetIfNew: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("prefer_relative_date") private var relativeDate = false

    var body: some View {
        Form {
            Section(header: Text("Content")) {
                FlashcardTextFields(flashcard: flashcard, autoFocus: autoFocus)
            }

            Section(header: Text("Tags")) {
                TagSelectionList(
                    selectedTags: flashcard.tags ?? [],
                    addTag: { flashcard.add(tag: $0) },
                    removeTags: { flashcard.remove(tagOffsets: $0) })
            }

            Section(header: Text("Notes")) {
                TextField(
                    "Notes", text: bindToProperty(of: flashcard, \.notes),
                    axis: .vertical)
            }

            if flashcard.modelContext != nil {
                Section(header: Text("Information")) {
                    LabeledContent {
                        DateText(
                            date: flashcard.creationDate,
                            relative: $relativeDate)
                    } label: {
                        Text("Created")
                    }
                    LabeledContent {
                        DateText(
                            date: flashcard.modificationDate,
                            relative: $relativeDate)
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
                modelContext.delete(flashcard)
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onChange(of: flashcard.front) { manageSaveState() }
        .onChange(of: flashcard.back) { manageSaveState() }
        .onChange(of: flashcard.notes) { manageSaveState() }
        .onDisappear {
            if let resetIfNew, !flashcard.isEmpty { resetIfNew() }
        }
    }

    private func manageSaveState() {
        if resetIfNew != nil {
            flashcard.insertIfNonEmpty(to: modelContext)
        }
    }
}

struct PendingFlashcardEditor: View {
    let tag: FlashcardTag?

    @State private var pendingFlashcard = Flashcard()

    var body: some View {
        FlashcardEditor(
            flashcard: pendingFlashcard,
            autoFocus: true,
            resetIfNew: { pendingFlashcard = .init() }
        )
        .onAppear {
            if let tag {
                pendingFlashcard.add(tag: tag)
            }
        }
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
        relative: true)

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
        FlashcardEditor(flashcard: anyFlashcard, autoFocus: false, resetIfNew: nil)
    }
    .modelContainer(container)
}

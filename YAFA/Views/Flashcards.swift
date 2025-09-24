import SwiftData
import SwiftUI

struct FlashcardsView: View {
    private struct Import: Hashable {}

    @Binding var focusedFlashcard: Flashcard?

    let searchText: String
    let searchTags: [FlashcardTag]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @Query(sort: \Flashcard.nextReviewDate) private var flashcards: [Flashcard]
    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]

    @State private var selectedFlashcards = Set<Flashcard>()

    /// Cards to display in an export sheet. If empty, do not display the export sheet.
    ///
    /// Ideally we would use `selectedFlashcards` here, but opening a sheet will exit the
    /// `editMode`, which further deselects all flashcards. As a workaround, when we open the export
    /// sheet, we save the selected flashcards to this variable.
    @State private var selectedFlashcardsForExportSheet: Set<Flashcard> = .init()

    var body: some View {
        GroupedFlashcards(
            flashcards: flashcards,
            focusedFlashcard: $focusedFlashcard,
            searchText: searchText,
            selectedTags: searchTags,
            selectedFlashcards: $selectedFlashcards
        )
        .toolbar {
            if editMode?.wrappedValue.isEditing == true {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Select all") {
                        selectedFlashcards.formUnion(flashcards)
                    }
                    .disabled(selectedFlashcards.count == flashcards.count)
                }
            }

            if editMode?.wrappedValue.isEditing == true {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TagsButton(
                        selectedFlashcards: selectedFlashcards,
                        tags: allTags
                    )
                    .disabled(selectedFlashcards.isEmpty)

                    Button("Export") {
                        selectedFlashcardsForExportSheet = selectedFlashcards
                    }
                    .disabled(selectedFlashcards.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Import", value: Import()).navigationDestination(
                        for: Import.self
                    ) { _ in ImportView(selectedTags: searchTags) }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: showExportSheet) {
            ExportSheet(flashcards: selectedFlashcardsForExportSheet)
        }
    }

    private var showExportSheet: Binding<Bool> {
        Binding {
            !selectedFlashcardsForExportSheet.isEmpty
        } set: {
            if !$0 {
                selectedFlashcardsForExportSheet = .init()
            }
        }
    }
}

private struct TagsButton: View {
    let selectedFlashcards: Set<Flashcard>
    let tags: [FlashcardTag]

    var body: some View {
        Menu {
            ForEach(tags) { tag in
                let flashcardsWithTag = selectedFlashcards.count {
                    $0.has(tag: tag)
                }

                if flashcardsWithTag == 0 {
                    Button(tag.name) {
                        for flashcard in selectedFlashcards {
                            flashcard.add(tag: tag)
                        }
                    }
                } else {
                    Button(
                        tag.name,
                        systemImage: flashcardsWithTag == selectedFlashcards.count
                            ? "checkmark" : "circlebadge"
                    ) {
                        for flashcard in selectedFlashcards {
                            flashcard.remove(tag: tag)
                        }
                    }
                }
            }
        } label: {
            Text("Tags")
        }
        .menuActionDismissBehavior(.disabled)
    }
}

private struct GroupedFlashcards: View {
    let flashcards: [Flashcard]
    @Binding var focusedFlashcard: Flashcard?
    let searchText: String
    let selectedTags: [FlashcardTag]

    @Binding var selectedFlashcards: Set<Flashcard>

    @State private var groups: [FlashcardGroup] = []
    @State private var flashcardsSearch: SearchDictionary<Flashcard> = .init()

    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @State private var allTagsSearch: SearchDictionary<FlashcardTag> = .init()

    @State private var editFlashcard: Flashcard?

    var body: some View {
        List(selection: $selectedFlashcards) {
            ForEach(groups) { group in
                Section(header: Text(group.dueDate)) {
                    ForEach(group.flashcards, id: \.self) { flashcard in
                        // Here we would like to use `NavigationLink(value: flashcard)`, but for
                        // some reason this doesn't work when `List(selection:)` is used above. We
                        // don't have any other way of having a selection, so we avoid using
                        // `NavigationLink()`, using `navigationDestination(item:)` instead with a
                        // button and custom array. https://stackoverflow.com/q/78866705
                        Button {
                            editFlashcard = flashcard
                        } label: {
                            HStack {
                                FlashcardItem(
                                    focusedFlashcard: $focusedFlashcard,
                                    flashcard: flashcard,
                                    tags: allTags,
                                    tagsSearch: allTagsSearch
                                )

                                Image(systemName: "chevron.right").foregroundStyle(.secondary).tint(
                                    .primary
                                )
                            }
                            .contextMenu {
                                let now = Date.now

                                if !flashcard.isDoneForNow(now: now) {
                                    Button("Study now", systemImage: "timer") {
                                        flashcard.nextReviewDate = now
                                    }
                                    .tint(.primary)
                                }

                                Button("Delete flashcard", systemImage: "trash", role: .destructive)
                                {
                                    flashcard.modelContext?.delete(flashcard)
                                }
                                .tint(.red)
                            }
                        }
                        .id(flashcard)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            let flashcard = group.flashcards[offset]

                            flashcard.modelContext?.delete(flashcard)
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $editFlashcard) { flashcard in
            FlashcardEditor(flashcard: flashcard, autoFocus: false)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: searchText, initial: true) { old, new in
            if new.isEmpty {
                flashcardsSearch = .init()
            } else if old.isEmpty {
                // We search for matches anywhere in the front or back string, so we use a
                // concatenation of the two as a search key.
                flashcardsSearch = .init(flashcards) { "\($0.front) \($0.back)" }
            }

            updateGroups()
        }
        .onChange(of: flashcards, initial: true) {
            if !searchText.isEmpty {
                // Update the search cache.
                flashcardsSearch = .init(flashcards) { "\($0.front) \($0.back)" }
            }

            updateGroups()
        }
        .onChange(of: allTags, initial: true) {
            allTagsSearch = .init(allTags, by: \.name)
        }
        .onChange(of: selectedTags) {
            updateGroups()
        }
    }

    private func updateGroups() {
        var neverStudiedFlashcards = [Flashcard]()
        var flashcardsByDueOffset: [Int: [Flashcard]] = [:]

        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        let filteredFlashcards =
            searchText.isEmpty
            ? AnySequence(flashcards)
            : AnySequence(flashcardsSearch.including(searchText))

        for flashcard in filteredFlashcards {
            guard selectedTags.allSatisfy({ flashcard.has(tag: $0) }) else { continue }

            if flashcard.reviews?.isEmpty != false {
                neverStudiedFlashcards.append(flashcard)
                continue
            }

            let flashcardTime = flashcard.nextReviewDate
            let flashcardDate = calendar.startOfDay(for: flashcardTime)
            let daysBetweenTodayAndDue = calendar.dateComponents(
                [.day],
                from: today,
                to: flashcardDate
            ).day!
            let offset = max(daysBetweenTodayAndDue, 0)

            flashcardsByDueOffset[offset, default: []].append(flashcard)
        }

        groups = []

        if !neverStudiedFlashcards.isEmpty {
            groups.append(
                .init(dueDate: "Never studied", flashcards: neverStudiedFlashcards)
            )
        }

        for (daysBetweenTodayAndDue, flashcards) in flashcardsByDueOffset.sorted(by: {
            $0.key < $1.key
        }) {
            let dueDateText =
                if daysBetweenTodayAndDue == 0 {
                    "Due today"
                } else if daysBetweenTodayAndDue == 1 {
                    "Due tomorrow"
                } else {
                    "Due in \(daysBetweenTodayAndDue) days"
                }

            groups.append(
                .init(dueDate: dueDateText, flashcards: flashcards)
            )
        }
    }
}

private struct FlashcardGroup: Identifiable {
    let dueDate: String
    var flashcards: [Flashcard]

    var id: String { dueDate }
}

#Preview {
    // Use a `NavigationStack` to display the top bar.
    NavigationStack {
        FlashcardsView(focusedFlashcard: .constant(nil), searchText: "", searchTags: [])
            .modelContainer(previewModelContainer())
    }
}

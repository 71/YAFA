import SwiftData
import SwiftUI

struct FlashcardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @Query(sort: \Flashcard.nextReviewDate) private var flashcards: [Flashcard]
    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]

    @State private var searchText: String = ""
    @State private var filteredFlashcards: [Flashcard] = []
    @State private var filteredTags: [FlashcardTag] = []
    @State private var selectedTags: [FlashcardTag] = []
    @State private var groupedFilteredFlashcards: [FlashcardGroup] = []
    @State private var pendingFlashcards = [Flashcard()]
    @State private var selectedFlashcards = Set<Flashcard>()

    private var isSearching: Bool {
        !searchText.isEmpty || !selectedTags.isEmpty
    }

    var body: some View {
        GroupedFlashcards(
            groups: groupedFilteredFlashcards, searching: isSearching,
            onPendingFlashcardChange: { _ in updatePendingFlashcards() },
            pendingFlashcards: $pendingFlashcards,
            selectedFlashcards: $selectedFlashcards
        )
        .navigationTitle("Flashcards")
        .toolbar {
            if editMode?.wrappedValue.isEditing == true {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        selectedFlashcards.formUnion(flashcards)
                    } label: {
                        Text("Select all")
                    }
                }
            }

            if editMode?.wrappedValue.isEditing == true {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TagsButton(
                        selectedFlashcards: selectedFlashcards,
                        tags: allTags
                    )
                    .disabled(selectedFlashcards.isEmpty)

                    ExportButton(flashcards: selectedFlashcards)
                        .disabled(selectedFlashcards.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ImportView()
                    } label: {
                        Text("Import")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .navigationBarBackButtonHidden(editMode?.wrappedValue.isEditing == true)
        .searchable(
            text: $searchText, tokens: $selectedTags,
            suggestedTokens: .constant(allTags),
            placement: .navigationBarDrawer(displayMode: .always)
        ) { token in
            Text(token.name)
        }
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: flashcards, initial: true) { updateSearchResults() }
        .onChange(of: searchText) { updateSearchResults() }
        .onChange(of: selectedTags) { updateSearchResults() }
    }

    private func updatePendingFlashcards() {
        if let firstEmpty = pendingFlashcards.first(where: \.isEmpty) {
            pendingFlashcards.removeAll(where: { $0.isEmpty && $0 != firstEmpty })
        } else {
            pendingFlashcards.append(.init())
        }

        updateSearchResults()
    }

    private func updateSearchResults() {
        let pendingSet = Set(pendingFlashcards)

        if !isSearching {
            filteredFlashcards = flashcards.filter { !pendingSet.contains($0) }
        } else {
            filteredFlashcards = flashcards.filter { flashcard in
                !pendingSet.contains(flashcard)
                    && selectedTags.allSatisfy { flashcard.has(tag: $0) }
                    && (searchText.isEmpty
                        || flashcard.front.localizedCaseInsensitiveContains(
                            searchText)
                        || flashcard.back.localizedCaseInsensitiveContains(
                            searchText))
            }
        }

        var neverStudiedFlashcards = [Flashcard]()
        var flashcardsByDueOffset: [Int: [Flashcard]] = [:]

        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        for flashcard in filteredFlashcards {
            if flashcard.reviews?.isEmpty != false {
                neverStudiedFlashcards.append(flashcard)
                continue
            }
            
            let flashcardTime = flashcard.nextReviewDate
            let flashcardDate = calendar.startOfDay(for: flashcardTime)
            let daysBetweenTodayAndDue = calendar.dateComponents(
                [.day], from: today, to: flashcardDate
            ).day!
            let offset = max(daysBetweenTodayAndDue, 0)
            
            flashcardsByDueOffset[offset, default: []].append(flashcard)
        }

        groupedFilteredFlashcards = []

        if !neverStudiedFlashcards.isEmpty {
            groupedFilteredFlashcards.append(
                .init(dueDate: "Never studied", flashcards: neverStudiedFlashcards)
            )
        }

        for (daysBetweenTodayAndDue, flashcards) in flashcardsByDueOffset.sorted(by: { $0.key < $1.key }) {
            let dueDateText = if daysBetweenTodayAndDue == 0 {
                "Due today"
            } else if daysBetweenTodayAndDue == 1 {
                "Due tomorrow"
            } else {
                "Due in \(daysBetweenTodayAndDue) days"
            }

            groupedFilteredFlashcards.append(
                .init(dueDate: dueDateText, flashcards: flashcards)
            )
        }
    }

    private func deleteItems(indices: IndexSet) {
        let filtered = filteredFlashcards

        withAnimation {
            for index in indices {
                modelContext.delete(filtered[index])
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
                    Button {
                        for flashcard in selectedFlashcards {
                            flashcard.add(tag: tag)
                        }
                    } label: {
                        Text(tag.name)
                    }
                } else {
                    Button {
                        for flashcard in selectedFlashcards {
                            flashcard.remove(tag: tag)
                        }
                    } label: {
                        Label(
                            tag.name,
                            systemImage: flashcardsWithTag
                                == selectedFlashcards.count
                                ? "checkmark" : "circlebadge")
                    }
                }
            }
        } label: {
            Text("Tags")
        }
        .menuActionDismissBehavior(.disabled)
    }
}

private struct ExportButton: View {
    let flashcards: Set<Flashcard>

    @State private var isOpened = false

    var body: some View {
        Button("Export") {
            isOpened.toggle()
        }
        .sheet(isPresented: $isOpened) {
            ExportSheet(flashcards: flashcards)
        }
    }
}

private struct GroupedFlashcards: View {
    let groups: [FlashcardGroup]
    let searching: Bool
    let onPendingFlashcardChange: (Flashcard) -> Void
    @Binding var pendingFlashcards: [Flashcard]
    @Binding var selectedFlashcards: Set<Flashcard>

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(selection: $selectedFlashcards) {
            if !searching {
                Section(header: Text("New card")) {
                    ForEach(pendingFlashcards) { pendingFlashcard in
                        NavigationLink {
                            FlashcardEditor(
                                flashcard: pendingFlashcard,
                                resetIfNew: {
                                    pendingFlashcards.removeAll {
                                        $0 == pendingFlashcard
                                    }
                                    onPendingFlashcardChange(pendingFlashcard)
                                })
                        } label: {
                            FlashcardItem(
                                flashcard: pendingFlashcard,
                                resetIfNew: {
                                    pendingFlashcards.removeAll {
                                        $0 == pendingFlashcard
                                    }
                                    onPendingFlashcardChange(pendingFlashcard)
                                })
                        }
                        .onChange(of: pendingFlashcard.isEmpty) {
                            onPendingFlashcardChange(pendingFlashcard)
                        }
                    }
                }
                .selectionDisabled()
            }

            ForEach(groups) { group in
                Section(header: Text(group.dueDate)) {
                    ForEach(group.flashcards, id: \.self) { flashcard in
                        NavigationLink {
                            FlashcardEditor(
                                flashcard: flashcard, resetIfNew: nil)
                        } label: {
                            FlashcardItem(flashcard: flashcard, resetIfNew: nil)
                        }
                        .id(flashcard)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            modelContext.delete(group.flashcards[offset])
                        }
                    }
                }
            }
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
        FlashcardsView().modelContainer(previewModelContainer())
    }
}

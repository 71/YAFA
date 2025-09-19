import SwiftData
import SwiftUI

struct FlashcardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @Query(sort: \Flashcard.nextReviewDate) private var flashcards: [Flashcard]
    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]

    @State private var searchText: String = ""
    @State private var filteredTags: [FlashcardTag] = []
    @State private var selectedTags: [FlashcardTag] = []
    @State private var selectedFlashcards = Set<Flashcard>()

    var body: some View {
        GroupedFlashcards(
            flashcards: flashcards,
            searchText: searchText,
            selectedTags: selectedTags,
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
    }
}

struct TagFlashcardsView: View {
    let tag: FlashcardTag

    @State private var selectedFlashcards = Set<Flashcard>()

    var body: some View {
        GroupedFlashcards(
            flashcards: tag.committedFlashcards,
            searchText: "",
            selectedTags: [tag],
            selectedFlashcards: $selectedFlashcards
        )
        .scrollContentBackground(.hidden)
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
    let flashcards: [Flashcard]
    let searchText: String
    let selectedTags: [FlashcardTag]

    @Binding var selectedFlashcards: Set<Flashcard>

    @Environment(\.modelContext) private var modelContext

    @State private var pendingFlashcards = [Flashcard()]
    @State private var groups: [FlashcardGroup] = []
    @State private var flashcardsSearch: SearchDictionary<Flashcard> = .init()

    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @State private var allTagsSearch: SearchDictionary<FlashcardTag> = .init()

    var body: some View {
        List(selection: $selectedFlashcards) {
            if !pendingFlashcards.isEmpty {
                Section(header: Text("New")) {
                    ForEach(pendingFlashcards) { pendingFlashcard in
                        NavigationLink {
                            FlashcardEditor(
                                flashcard: pendingFlashcard,
                                autoFocus: true
                            )
                        } label: {
                            FlashcardItem(
                                flashcard: pendingFlashcard,
                                allTagsSearch: allTagsSearch
                            )
                        }
                        .saveIfNonEmpty(
                            or: searchText,
                            flashcard: pendingFlashcard,
                            withTags: selectedTags,
                            in: modelContext
                        )
                        .onChange(of: pendingFlashcard.front) {
                            handlePendingFlashcardChange(pendingFlashcard)
                        }
                        .onChange(of: pendingFlashcard.back) {
                            handlePendingFlashcardChange(pendingFlashcard)
                        }
                    }
                }
                .selectionDisabled()
            }

            ForEach(groups) { group in
                Section(header: Text(group.dueDate)) {
                    ForEach(group.flashcards) { flashcard in
                        NavigationLink {
                            FlashcardEditor(
                                flashcard: flashcard, autoFocus: false)
                        } label: {
                            FlashcardItem(flashcard: flashcard, allTagsSearch: allTagsSearch)
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
        .onChange(of: searchText, initial: true) { old, new in
            if new.isEmpty {
                flashcardsSearch = .init()

                // Add a pending flashcard if we removed it before.
                pendingFlashcards.removeAll()
                pendingFlashcards.append(.init(tags: selectedTags))

                updateGroups()

                return
            }

            let hasExactMatch = flashcards.contains { $0.front == searchText }

            if old.isEmpty {
                // We search for matches anywhere in the front or back string, so we use a
                // concatenation of the two as a search key.
                flashcardsSearch = .init(flashcards) { "\($0.front) \($0.back)" }

                // When searching, make sure we only have one pending flashcard corresponding to the
                // search text.
                pendingFlashcards.removeAll()

                if !hasExactMatch {
                    pendingFlashcards.append(.init(front: searchText, tags: selectedTags))
                }
            } else if hasExactMatch {
                pendingFlashcards.removeAll()
            } else {
                // We simply update search results.
                if let first = pendingFlashcards.first {
                    // Update the existing pending flashcard.
                    first.front = searchText
                } else {
                    // We likely had an exact match before.
                    pendingFlashcards.append(.init(front: searchText, tags: selectedTags))
                }
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
    }

    private func handlePendingFlashcardChange(_ flashcard: Flashcard) {
        if !searchText.isEmpty {
            // If searching, don't add empty pending flashcards.
            return
        }

        if flashcard.isEmpty {
            // We are now empty, clean up if there is another empty flashcard.
            if let i = pendingFlashcards.firstIndex(where: { $0.isEmpty && $0 != flashcard }) {
                pendingFlashcards.remove(at: i)
            }
        } else {
            // If we were empty and there is no other empty flashcard, add one.
            if !pendingFlashcards.contains(where: { $0.isEmpty }) {
                pendingFlashcards.append(.init(tags: selectedTags))
            }
        }
    }

    private func updateGroups() {
        var neverStudiedFlashcards = [Flashcard]()
        var flashcardsByDueOffset: [Int: [Flashcard]] = [:]

        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        let pendingSet = Set(pendingFlashcards)

        let filteredFlashcards = searchText.isEmpty
            ? AnySequence(flashcards)
            : AnySequence(flashcardsSearch.including(searchText))

        for flashcard in filteredFlashcards {
            guard !pendingSet.contains(flashcard) else { continue }
            guard selectedTags.allSatisfy({ flashcard.has(tag: $0 )}) else { continue }

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
        FlashcardsView().modelContainer(previewModelContainer())
    }
}

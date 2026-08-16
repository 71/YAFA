import SwiftData
import SwiftUI

/// The search bar shown in study / term list views.
struct SearchBar: View {
    private struct NewTermFromSearch: Hashable {}

    @Binding var searchText: String
    @Binding var searchTags: [Tag]
    @Binding var searchUntagged: Bool
    @Binding var searching: Bool

    /// The term being edited in the list, if any. While one is focused the bar stops being a search
    /// field and offers that term's tags instead: searching is not what the bottom of the screen is
    /// for mid-edit, and this saves the tag strip from having to appear inside the row.
    let focusedTerm: Term?

    let tags: [Tag]
    let undo: (() -> Void)?

    // Search state
    //
    @FocusState private var isFocused: Bool
    @State private var selection: TextSelection?

    // Terms, used to tell whether the search text names a term which already exists.
    //
    @Query private var allTerms: [Term]

    var body: some View {
        GlassEffectContainer {

            //
            // MARK: Tag selection

            if let focusedTerm {
                // Editing a term: the bar offers its tags, so applying one is a tap rather than
                // typing "#" into the term's own text.
                TermTagsBar(term: focusedTerm, tags: tags)
            } else if searching {
                TextFieldTags(
                    text: $searchText,
                    selection: $selection,
                    showUntagged: $searchUntagged,
                    tags: tags,
                    selectedTags: searchTags
                ) { addedTag in
                    searchTags.append(addedTag)
                } onRemove: { removedTag in
                    if let index = searchTags.firstIndex(of: removedTag) {
                        searchTags.remove(at: index)
                    }
                }
            }

            // The search field is hidden while a term is being edited: the bar is showing that
            // term's tags, and searching is not what the bottom of the screen is for mid-edit.
            if focusedTerm == nil {
                HStack {

                //
                // MARK: Undo/Close buttons

                if !searching, let undo {
                    Button {
                        undo()
                    } label: {
                        BarButtonLabel("Undo", systemImage: "arrow.uturn.backward")
                    }
                }

                if !searchText.isEmpty && !allTerms.contains(where: { $0.text == searchText }) {
                    // Make sure to use `navigationDestination()` to _not_ create the editor until
                    // the button is clicked.
                    NavigationLink(value: NewTermFromSearch()) {
                        BarButtonLabel("Create new", systemImage: "plus")
                    }
                }

                //
                // MARK: Search field

                TextField("Search or add...", text: $searchText, selection: $selection)
                    .safeAreaInset(edge: .leading) {
                        Image(systemName: "magnifyingglass")
                            .resizable()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                    .overlay(alignment: .trailing) {
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.secondary)
                                    .padding(8) // Pad in all directions for a larger tap surface.
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .focused($isFocused)
                    .clipShape(Capsule())
                    .padding(12)
                    .glassEffect(.regular.interactive())

                }
                .labelStyle(.iconOnly)
            }
        }
        .navigationDestination(for: NewTermFromSearch.self) { _ in
            NewTermEditor(text: searchText, tags: searchTags)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .tint(.primary)
        .buttonStyle(.glass)

        .animation(.default, value: searchText)
        .animation(.default, value: searching)

        .onChange(of: isFocused) {
            if isFocused {
                searching = true
            }
        }

        // We could use `.searchable()` and `.toolbar()` here, which takes care of a lot of logic
        // for us (e.g. showing the `magnifyingglass` and `xmark` button). However, this approach
        // doesn't allow us to add a leading button to the toolbar while it is focused, which we
        // need for the "add" button. We _could_ just put this button somewhere else, but I prefer
        // the current approach.
        //
        // .searchable(text: $searchText, placement: .toolbarPrincipal, prompt: "Search or add...")
        // .toolbarVisibility(.hidden, for: .navigationBar)
        // .toolbar {
        //     ToolbarItem(placement: .bottomBar) {
        //         Button("Undo", systemImage: "arrow.uturn.backward") {}
        //     }
        //
        //     ToolbarSpacer(placement: .bottomBar)
        //     DefaultToolbarItem(kind: .search, placement: .bottomBar)
        //     ToolbarSpacer(placement: .bottomBar)
        //
        //     ToolbarItem(placement: .bottomBar) {
        //         Button {} label: { Label("New", systemImage: "plus") }
        //     }
        // }
        // .tint(.primary)
    }
}

private struct BarButtonLabel: View {
    let text: LocalizedStringKey
    let systemImage: String
    let size: CGFloat

    init(_ text: LocalizedStringKey, systemImage: String, size: CGFloat = 18) {
        self.text = text
        self.systemImage = systemImage
        self.size = size
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .imageScale(.large)
            .frame(width: size, height: size)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
    }
}

/// The tags of the term being edited, offered as buttons: applied ones first, then the rest.
///
/// This takes the place of the search field while a term is focused, so that tagging is a tap on
/// something already on screen rather than a "#" typed into the term's own text.
private struct TermTagsBar: View {
    let term: Term
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext

    /// Tags indexed for search, so that "#ㅎ" finds "한국어" the way the rest of the app's searching
    /// does. Rebuilt only when the tags change rather than on every keystroke.
    @State private var search: SearchDictionary<Tag> = .init()

    var body: some View {
        // Typing "#" in the term filters this bar, and what follows it names a tag to create if
        // nothing matches. That keeps one list of tags on screen instead of two.
        let entry = trailingTagEntry(in: term.text)
        let query = entry?.name ?? ""
        let selected = term.tags ?? []
        let selectedIDs = Set(selected.map(\.persistentModelID))
        let matching = matchingIDs(for: query)
        let selectedMatches = selected.filter { matching?.contains($0.persistentModelID) ?? true }
        let unselected = tags.filter {
            !selectedIDs.contains($0.persistentModelID)
                && (matching?.contains($0.persistentModelID) ?? true)
        }
        let exists = tags.contains { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }

        ScrollView(.horizontal) {
            HStack {
                if !query.isEmpty && !exists {
                    Button(query, systemImage: "plus") {
                        let tag = Tag(name: query)

                        modelContext.insert(tag)
                        apply(tag, entry: entry)
                    }
                }

                ForEach(selectedMatches) { tag in
                    Button(tag.name) {
                        term.remove(tag: tag)
                        clear(entry)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                }

                ForEach(unselected) { tag in
                    Button(tag.name) { apply(tag, entry: entry) }
                }
            }
            .glassEffectTransition(.identity)
        }
        .scrollIndicators(.hidden)
        .animation(.default, value: term.tags)
        .animation(.default, value: term.text)
        .onChange(of: tags, initial: true) { search = .init(tags, by: \.name) }
    }

    /// The ids of the tags matching `query`, or `nil` when there is nothing to filter by.
    private func matchingIDs(for query: String) -> Set<PersistentIdentifier>? {
        guard !query.isEmpty else { return nil }

        return Set(search.including(query).map(\.persistentModelID))
    }

    private func apply(_ tag: Tag, entry: (range: Range<String.Index>, name: String)?) {
        term.add(tag: tag)
        clear(entry)
    }

    /// Removes the "#…" which was being typed, now that it has been turned into a tag.
    private func clear(_ entry: (range: Range<String.Index>, name: String)?) {
        guard let entry else { return }

        term.text.removeSubrange(entry.range)
        term.text = term.text.trimmingCharacters(in: .whitespaces)
        term.touch()
    }
}

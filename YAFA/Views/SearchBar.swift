import SwiftUI

/// The search bar shown in study / flashcards views.
struct SearchBar: View {
    @Binding var searchText: String
    @Binding var searchTags: [FlashcardTag]
    @Binding var searching: Bool

    /// Whether an element outside of the search bar has focus.
    let outsideFocus: Bool

    let flashcards: [Flashcard]
    let tags: [FlashcardTag]
    let undo: (() -> Void)?

    // Search state
    //
    @FocusState private var isFocused: Bool
    @State private var selection: TextSelection?

    @Environment(\.isFocused) private var isAnyFocused

    // Undo state
    //
    @State private var lastReviewUndoStates: [FlashcardReviewUndo] = []

    var body: some View {
        GlassEffectContainer {

            //
            // MARK: Tag selection

            if searching && !outsideFocus {
                TextFieldTags(
                    text: $searchText,
                    selection: $selection,
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

                if !searchText.isEmpty && !flashcards.contains(where: { $0.front == searchText }) {
                    NavigationLink {
                        NewFlashcardEditor(text: searchText, tags: searchTags)
                    } label: {
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
                    .safeAreaInset(edge: .trailing) {
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .focused($isFocused)
                    .clipShape(Capsule())
                    .padding(12)
                    .glassEffect(.regular.interactive())

                //
                // MARK: Close button

                if searching {
                    Button {
                        selection = nil
                        searching = false
                        isFocused = false
                        searchText = ""
                        searchTags = []
                    } label: {
                        BarButtonLabel("Close", systemImage: "xmark")
                    }
                }
            }
            .labelStyle(.iconOnly)
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
    let text: String
    let systemImage: String
    let size: CGFloat

    init(_ text: String, systemImage: String, size: CGFloat = 18) {
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

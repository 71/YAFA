import SwiftData
import SwiftUI

/// The tags applied to something, plus a field for adding more.
///
/// Adding works the way adding a link does: type, and the tags which match appear underneath;
/// submitting creates a tag with the text as typed. A menu would have to list every tag at once,
/// which stops being usable well before a search field does.
struct TagSelectionList: View {
    let selectedTags: [Tag]
    let addTag: (Tag) -> Void
    let removeTags: (IndexSet) -> Void

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var newTagText = ""
    @State private var matches: [Tag] = []
    @FocusState private var focusedTag: Tag?
    @FocusState private var addingTag: Bool

    var body: some View {
        ForEach(selectedTags) { tag in
            TextField("Tag name", text: bindToProperty(of: tag, \.name))
                .focused($focusedTag, equals: tag)
        }
        .onDelete { removeTags($0) }

        TextField("Add tag", text: $newTagText)
            .focused($addingTag)
            .onSubmit { add(newTag()) }
            .onChange(of: allTags, initial: true) { updateMatches() }
            .onChange(of: selectedTags) { updateMatches() }
            .onChange(of: newTagText) { updateMatches() }
            // Losing focus with text still in the field commits it, the same as submitting would:
            // leaving the text and its suggestions sitting there afterwards would be a half-made
            // tag which nothing else will finish.
            .onChange(of: addingTag) { _, focused in
                if !focused { add(newTag()) }
            }

        SuggestionsCard(items: matches) { match in
            SuggestedTagRow(tag: match, matching: trimmedText) { add(match) }
        }
    }

    /// Tags matching what has been typed, excluding those already applied.
    private func updateMatches() {
        let text = trimmedText

        guard !text.isEmpty else {
            matches = []
            return
        }

        let selected = Set(selectedTags.map(\.persistentModelID))

        matches = allTags
            .filter { !selected.contains($0.persistentModelID) }
            .filter { $0.name.localizedCaseInsensitiveContains(text) }
            .prefix(10)
            .map { $0 }
    }

    private var trimmedText: String {
        newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The tag with this exact name, or a new one. Reusing an exact match keeps typing an existing
    /// tag's name from quietly creating a second tag with the same name.
    private func newTag() -> Tag? {
        let text = trimmedText

        guard !text.isEmpty else { return nil }

        if let existing = allTags.first(where: { $0.name == text }) {
            return existing
        }

        let tag = Tag(name: text)

        modelContext.insert(tag)

        return tag
    }

    private func add(_ tag: Tag?) {
        guard let tag else { return }

        addTag(tag)
        newTagText = ""
        updateMatches()
    }
}

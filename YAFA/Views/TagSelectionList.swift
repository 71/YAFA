import SwiftData
import SwiftUI

/// The tags applied to something, plus a field for adding more.
///
/// Adding works the way adding a link does: type, and the tags which match appear underneath;
/// submitting creates a tag with the text as typed. A menu would have to list every tag at once,
/// which stops being usable well before a search field does.
///
/// Before anything is typed the field offers the tags used most recently instead. Tagging tends to
/// come in runs -- several terms from one lesson, all wanting the same one or two tags -- so the
/// tag wanted next is usually the tag wanted last, and finding it should not require remembering
/// its name.
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
        ForEach(Array(selectedTags.enumerated()), id: \.element.id) { (index, tag) in
            TextField("Tag name", text: bindToProperty(of: tag, \.name))
                .focused($focusedTag, equals: tag)
                // The swipe is still the quick way; the menu is here so a row explains what it can
                // do, the way the link rows above it already do.
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { focusedTag = tag }
                        .tint(.primary)

                    // Untagging leaves the tag itself alone -- it may be on other terms, and the
                    // caller offers to delete it when it is not.
                    Button("Remove tag", systemImage: "tag.slash", role: .destructive) {
                        removeTags(IndexSet(integer: index))
                    }
                    .tint(.red)
                }
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
                if focused {
                    // What counts as recent may have moved on since the field was last used.
                    updateMatches()
                } else {
                    add(newTag())
                }
            }

        // Only while the field has focus: recent tags are an aid to typing in it, and a card of
        // them sitting under an idle form would read as part of the term rather than as a prompt.
        SuggestionsCard(items: addingTag ? matches : []) { match in
            SuggestedTagRow(tag: match, matching: trimmedText) { add(match) }
        }
    }

    /// How many tags to offer, whether matched or merely recent.
    private static let suggestionLimit = 10

    /// Tags matching what has been typed, or the most recently used ones before anything is.
    ///
    /// Either way those already applied are left out: they are listed above, and offering one again
    /// would suggest adding what is already there.
    private func updateMatches() {
        let text = trimmedText
        let selected = Set(selectedTags.map(\.persistentModelID))
        let available = allTags.filter { !selected.contains($0.persistentModelID) }

        guard !text.isEmpty else {
            matches = recent(among: available)
            return
        }

        matches = available
            .filter { $0.name.localizedCaseInsensitiveContains(text) }
            .prefix(Self.suggestionLimit)
            .map { $0 }
    }

    /// Tags ordered by when they were last applied, most recent first.
    ///
    /// A tag which predates `lastUsedDate`, or which has never been applied to anything, sorts last:
    /// that is where a tag made and then abandoned belongs, and guessing a date for one which never
    /// recorded it would put it above tags genuinely used.
    private func recent(among tags: [Tag]) -> [Tag] {
        tags
            .sorted { ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast) }
            .prefix(Self.suggestionLimit)
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

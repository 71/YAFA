import SwiftData
import SwiftUI

/// The list of tags, with what each holds and whether it is being studied.
///
/// Tags are otherwise created by typing "#" into a term, which only works if you already know to do
/// it; this screen is where someone goes looking for them, so it offers the same thing as a button.
struct Tags: View {
    @Binding var searchTags: [Tag]

    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext

    /// The tag just added, which takes the keyboard so that a new row is named rather than left
    /// sitting there as "New tag".
    @FocusState private var newTag: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            Group {
                if tags.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addButton }
            }
        }
        // A tag added and then left unnamed is not a tag, and nothing else would ever clear it: it
        // would sit in this list, and in every tag bar, as a blank row.
        .onChange(of: newTag) { (previous, _) in
            guard let previous, let tag = tags.first(where: { $0.persistentModelID == previous }),
                tag.name.trimmingCharacters(in: .whitespaces).isEmpty
            else { return }

            modelContext.delete(tag)
        }
    }

    private var list: some View {
        List {
            ForEach(tags) { tag in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Tag", text: bindToProperty(of: tag, \.name))
                            .font(.headline)
                            .focused($newTag, equals: tag.persistentModelID)

                        Text(caption(of: tag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Tags no longer carry a study direction -- which directions are studied is
                    // decided per term by which links exist -- so all that is left is whether the
                    // tag's terms are studied at all. A switch says which way that is set far more
                    // plainly than a checkmark whose colours invert.
                    Toggle(
                        "Study",
                        isOn: Binding { tag.isStudying } set: { tag.isStudying = $0 }
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)

                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                }
                .contextMenu {
                    Button("Delete tag", systemImage: "trash", role: .destructive) {
                        tag.modelContext?.delete(tag)
                    }
                    .tint(.red)
                }
                .onTapGesture {
                    searchTags = [tag]
                }
            }
            .onDelete { indices in
                for index in indices.reversed() {
                    let tag = tags[index]

                    tag.modelContext?.delete(tag)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        // Rows carry no insets of their own, so the padding the header used to provide is applied
        // here instead.
        .padding(.horizontal, 16)
    }

    /// What is shown before there is a single tag, in place of an empty screen under the header.
    ///
    /// Says what tags are for rather than that there are none, which is the part someone arriving
    /// here for the first time does not already know.
    private var empty: some View {
        ContentUnavailableView {
            Label("No tags", systemImage: "tag")
        } description: {
            Text(
                "Tags group terms. Turn one off to leave its terms out of the study queue, or tap one to see everything it holds."
            )
        }
    }

    private var addButton: some View {
        Button("New tag", systemImage: "plus") {
            let tag = Tag(name: "")

            modelContext.insert(tag)

            // The row does not exist until the query takes the insert, so focus is asked for after
            // it lands rather than in the same pass.
            Task { newTag = tag.persistentModelID }
        }
        .labelStyle(.iconOnly)
    }
}

/// What the tag holds, and how much of it is due.
///
/// Whether the tag is being studied is left to the toggle beside it, which says so more plainly
/// than a word appended here.
///
/// The due figure counts reviews rather than terms, matching the header: a progress shared by
/// several links is one review however many terms carry it, so counting terms would say "4 due"
/// where the header says "2" and neither would be wrong.
private func caption(of tag: Tag) -> String {
    // Only the terms the list will actually show. A term which is nothing but the target of a link
    // -- a definition -- is hidden there, since the row studying it already spells it out, and the
    // migration tags both sides of every old flashcard. Counting all of them made a tag whose terms
    // were all definitions promise rows which were not there.
    let terms = (tag.terms ?? []).filter { $0.isStudied || $0.isUnlinked }

    guard !terms.isEmpty else {
        return String(localized: "No term")
    }

    let now = Date.now
    var due = Set<PersistentIdentifier>()

    // Both directions, matching what the study queue takes: a link is in this tag's group when
    // either of its terms carries the tag, so one reversed to point *at* a tagged term is still
    // studied under it and still has to be counted here.
    for term in terms {
        for link in term.relatedLinks.map(\.link) where !link.isDoneForNow(now: now) {
            guard let progress = link.progress else { continue }

            due.insert(progress.persistentModelID)
        }
    }

    if due.isEmpty {
        return String(localized: "\(terms.count) terms")
    }
    return String(localized: "\(due.count) due in \(terms.count) terms")
}

import SwiftData
import SwiftUI

struct Tags: View {
    @Binding var searchTags: [Tag]

    let tags: [Tag]

    var body: some View {
        List {
            ForEach(tags) { tag in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Tag", text: bindToProperty(of: tag, \.name))
                            .font(.headline)

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
        .padding(.top, 16)
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
    guard let terms = tag.terms, !terms.isEmpty else {
        return String(localized: "No term")
    }

    let now = Date.now
    var due = Set<PersistentIdentifier>()

    for term in terms {
        for link in term.studiedLinks where !link.isDoneForNow(now: now) {
            guard let progress = link.progress else { continue }

            due.insert(progress.persistentModelID)
        }
    }

    if due.isEmpty {
        return String(localized: "\(terms.count) terms")
    }
    return String(localized: "\(due.count) due in \(terms.count) terms")
}

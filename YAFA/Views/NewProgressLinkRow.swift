import SwiftData
import SwiftUI

/// The "add link" field at the end of a progress' link list.
///
/// Adding here takes two terms rather than one -- a progress has no term of its own to link from --
/// so the field is asked twice: first for the source, then for the target. Each step searches what
/// exists and offers to create, the same way the term view's field does.
struct NewProgressLinkRow: View {
    let progress: Progress

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Term.text) private var allTerms: [Term]

    @State private var text = ""
    /// The source term, once chosen. While this is `nil` the field is asking for the source.
    @State private var source: Term?
    @State private var termsSearch: SearchDictionary<Term> = .init()
    @State private var matches: [Term] = []

    /// A link which already carries review history, awaiting confirmation before it is moved.
    @State private var conflicting: Link?

    @FocusState private var adding: Bool

    var body: some View {
        if let source {
            ChosenSourceRow(source: source) { reset() }
        }

        HStack(spacing: 8) {
            // Only in the second step, where the field continues the row above it rather than
            // starting something new.
            if source != nil {
                Image(systemName: "arrow.turn.down.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            TextField(source == nil ? "Add link" : "Choose target", text: $text, axis: .vertical)
                .focused($adding)
        }
        .onSubmit { choose(term(named: trimmedText)) }
        // Losing focus with text still in the field commits it, the same as submitting would. In
        // the first step that means the source is chosen and the field moves on to asking for the
        // target, which is where it would have been left anyway.
        .onChange(of: adding) { _, focused in
            if !focused { choose(term(named: trimmedText)) }
        }
        .onChange(of: allTerms, initial: true) {
            termsSearch = .init(allTerms, by: \.text)
            updateMatches()
        }
        .onChange(of: text) { updateMatches() }
        .onChange(of: source) { updateMatches() }

        SuggestionsCard(items: matches) { match in
            SuggestedTermRow(term: match, matching: trimmedText) { choose(match) }
        }

        // Existing links from the chosen source, which can be joined instead of made anew.
        if let source {
            ForEach(joinableLinks(from: source)) { link in
                JoinableLinkRow(link: link) {
                    if link.progress?.reviews?.isEmpty == false {
                        conflicting = link
                    } else {
                        join(link)
                    }
                }
            }
        }

        EmptyView()
            .confirmationDialog(
                "This link already has progress",
                isPresented: Binding { conflicting != nil } set: { if !$0 { conflicting = nil } },
                titleVisibility: .visible,
                presenting: conflicting
            ) { link in
                Button("Add anyway", role: .destructive) { join(link) }
            } message: { link in
                Text(
                    "\(link.answerText) is scheduled separately and has its own review history, which will be discarded."
                )
            }
    }

    // MARK: Choosing

    /// Takes the next term: the source if none has been chosen yet, otherwise the target.
    private func choose(_ chosen: Term?) {
        guard let chosen else { return }

        guard let source else {
            source = chosen
            text = ""
            return
        }

        guard chosen.persistentModelID != source.persistentModelID else { return }

        // Reuse the link if these two terms are already connected, rather than making a second one.
        let existing = (source.outgoingLinks ?? []).first {
            $0.target?.persistentModelID == chosen.persistentModelID
        }

        if let existing {
            join(existing)
        } else {
            let link = Link(source: source, target: chosen, progress: progress)

            modelContext.insert(link)
            reset()
        }
    }

    private func join(_ link: Link) {
        link.join(progress: progress)
        conflicting = nil
        reset()
    }

    private func reset() {
        source = nil
        text = ""
        matches = []
    }

    // MARK: Suggestions

    private func updateMatches() {
        guard !trimmedText.isEmpty else {
            matches = []
            return
        }

        let excluded: Set<PersistentIdentifier> =
            if let source {
                // The source itself, plus anything it already links to, which is offered as a
                // joinable link below instead.
                Set([source.persistentModelID])
                    .union((source.outgoingLinks ?? []).compactMap { $0.target?.persistentModelID })
            } else {
                []
            }

        matches = termsSearch.including(trimmedText)
            .filter { !excluded.contains($0.persistentModelID) }
            .prefix(10)
            .map { $0 }
    }

    /// Links from `source` which are not already scheduled against this progress.
    private func joinableLinks(from source: Term) -> [Link] {
        let mine = Set(progress.sharers.map(\.persistentModelID))

        return source.sortedOutgoingLinks
            .filter { !mine.contains($0.persistentModelID) }
            .filter {
                trimmedText.isEmpty || $0.answerText.localizedCaseInsensitiveContains(trimmedText)
            }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The term with this exact text, or a new one.
    ///
    /// An exact match is reused rather than duplicated -- that is what makes two terms pointing at
    /// one definition synonyms rather than unrelated cards.
    private func term(named text: String) -> Term? {
        guard !text.isEmpty else { return nil }

        if let existing = allTerms.first(where: { $0.text == text }) {
            return existing
        }

        let term = Term(text: text)

        modelContext.insert(term)

        return term
    }
}

/// The chosen source, shown above the target field so it is clear what the link starts from.
private struct ChosenSourceRow: View {
    let source: Term
    let clear: () -> Void

    var body: some View {
        HStack {
            Text(source.text)

            Spacer()

            Button("Clear", systemImage: "xmark.circle.fill") { clear() }
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
    }
}

/// An existing link from the chosen source, offered for joining this progress.
private struct JoinableLinkRow: View {
    let link: Link
    let join: () -> Void

    var body: some View {
        Button(action: join) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.answerText)

                    if link.progress?.reviews?.isEmpty == false {
                        Text("Has its own progress")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "link")
                    .foregroundStyle(.tint)
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }
}

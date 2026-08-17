import SwiftUI

/// A term as shown in the term list: its text, plus what it is studied against.
///
/// Both lines are editable in place when the term has exactly one unanchored outgoing link -- the
/// shape every migrated flashcard has -- so the list keeps the quick two-field editing it had before
/// terms and links were separate things. A term linked to several others cannot be edited that way,
/// since there is no single target to bind to, so it shows them as text instead. Nor can an anchored
/// one: the second line would be a word taken out of the first, and a field under a sentence reads
/// as its definition rather than as one of its blanks.
///
/// A term whose text is a sentence or a definition is as long as it is; the row caps its height
/// rather than growing to fit. Editing it happens on its own screen, where there is room.
struct TermItem: View {
    @Binding var focusedTerm: Term?

    let term: Term

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TermTextField(focusedTerm: $focusedTerm, term: term, autoFocus: false, maxLines: 3)

            let links = term.sortedOutgoingLinks

            if links.count == 1, !links[0].isAnchored, let target = links[0].target {
                TextField(
                    "Definition",
                    text: bindToProperty(of: target, \.text),
                    axis: .vertical
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .onChange(of: target.text) { target.touch() }
            } else {
                TermTargets(term: term)
            }
        }
    }
}

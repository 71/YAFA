import SwiftUI

/// A term as shown in the term list: its text, plus what it is studied against.
///
/// Both lines are editable in place when the term has exactly one outgoing link -- the shape every
/// migrated flashcard has -- so the list keeps the quick two-field editing it had before terms and
/// links were separate things. A term linked to several others cannot be edited that way, since
/// there is no single target to bind to, so it shows them as text instead.
struct TermItem: View {
    @Binding var focusedTerm: Term?

    let term: Term

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TermTextField(focusedTerm: $focusedTerm, term: term, autoFocus: false)

            let links = term.sortedOutgoingLinks

            if links.count == 1, let target = links[0].target {
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

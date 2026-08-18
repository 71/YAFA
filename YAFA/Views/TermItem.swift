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
/// A term whose text is a sentence or a definition is as long as it is; the row caps both lines
/// rather than growing to fit, so that one long term cannot take the whole list. The definition
/// field lifts its cap while it is being edited -- what is being typed should stay in view -- but
/// only as far as ten lines, which is a tall row rather than a screenful. The term text keeps its
/// cap throughout: editing either at length happens on the term's own screen, where there is room.
struct TermItem: View {
    @Binding var focusedTerm: Term?

    let term: Term

    /// Whether the definition field is being edited, which lets it grow taller.
    @FocusState private var secondFieldFocused: Bool

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
                .focused($secondFieldFocused)
                // A number rather than `nil` for the focused case: `nil` asks the field for its
                // full intrinsic height, which a row inside a `List` does not grant, leaving the
                // cap looking stuck at three lines however focus changes.
                .lineLimit(secondFieldFocused ? 10 : 3)
                // Without this the row gives the text a single line's height and truncates the
                // rest, whatever the line limit says -- as in `TermTargets`.
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: target.text) { target.touch() }
            } else {
                TermTargets(term: term)
            }
        }
    }
}

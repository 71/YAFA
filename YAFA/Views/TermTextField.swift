import SwiftData
import SwiftUI

/// The text field holding a `Term`'s text.
///
/// Tagging happens in the bar at the bottom of the term list, which filters itself against whatever
/// follows a "#" typed here. Nothing is shown inline: the two used to appear together, offering the
/// same tags twice.
struct TermTextField: View {
    @Binding var focusedTerm: Term?

    let term: Term
    let autoFocus: Bool

    @FocusState private var focused: Bool

    var body: some View {
        TextField("Term", text: bindToProperty(of: term, \.text), axis: .vertical)
            .focused($focused)
            .onAppear { if autoFocus { focused = true } }

            .onChange(of: focused, initial: true) {
                if focused {
                    focusedTerm = term
                } else if focusedTerm == term {
                    // Unfocus the term _we_ marked as focused.
                    focusedTerm = nil
                }
            }
    }
}

/// The partial tag being typed at the end of `text`, if any: everything after a "#" which is not
/// followed by whitespace.
///
/// Returned with its range so that accepting a tag can strip the "#…" from the text it was typed
/// into.
func trailingTagEntry(in text: String) -> (range: Range<String.Index>, name: String)? {
    var index = text.endIndex

    while index != text.startIndex {
        let before = text.index(before: index)
        let scalar = text.unicodeScalars[before]

        if scalar == "#" {
            return (before..<text.endIndex, String(text[index...]))
        }

        guard !scalar.properties.isWhitespace else { return nil }

        index = before
    }

    return nil
}

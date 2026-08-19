import SwiftData
import SwiftUI

/// The text field holding a `Term`'s text, with its anchored spans tinted.
///
/// Tagging happens in the bar at the bottom of the term list, which filters itself against whatever
/// follows a "#" typed here. Nothing is shown inline: the two used to appear together, offering the
/// same tags twice.
///
/// A term whose links are anchored needs to show *where* they point, which plain text cannot do, so
/// the field is a `TextEditor` over an `AttributedString` rather than a `TextField`: it is the only
/// editable control which can carry a background colour over part of its text. Everything else is
/// arranged to keep it reading as the field it replaces -- a placeholder when empty, no chrome, and
/// no height beyond what the text needs.
struct TermTextField: View {
    @Binding var focusedTerm: Term?

    let term: Term
    let autoFocus: Bool

    /// Where the caret is, for the screens which act on the selection. `nil` for the ones which do
    /// not care.
    var selection: Binding<TextSelection?>? = nil

    /// The link whose anchors are drawn more strongly, if any.
    var emphasising: Link? = nil

    /// The only link whose anchors are tinted, if the field is standing in for one row rather than
    /// for the term as a whole. `nil` tints every anchor, which is what the term section wants.
    var highlighting: Link? = nil

    /// A prefix of this field's own text to tint, and the colour to tint it, for a row standing in
    /// for a link anchored elsewhere.
    ///
    /// Where `highlighting` lights the anchors *this* term owns, this lights a span of it which
    /// belongs to another term's sentence: the words that sentence blanked, shown here on the term
    /// they point at. Nothing is anchored here, so it is a range rather than a link.
    var tintingPrefix: (length: Int, color: Color)? = nil

    /// How tall the field is allowed to grow, in lines. `nil` lets it fit whatever it holds, which
    /// is what the editor wants; the term list caps it instead, since a term whose text is a
    /// definition would otherwise take the whole screen for one row.
    var maxLines: Int? = nil

    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22

    @FocusState private var focused: Bool

    /// The text as the editor holds it, which is `term.text` plus the anchor tints.
    ///
    /// Kept in state rather than recomputed per redraw: the editor writes into this binding as the
    /// user types, and the term is updated from it, not the other way around.
    @State private var text = AttributedString()
    @State private var editorSelection = AttributedTextSelection()

    var body: some View {
        synced
            .onChange(of: editorSelection) { publishSelection() }
            // The selection does not move while a CJK character is being composed (ㅎ -> 하), so the
            // text is watched alongside it.
            .onChange(of: text) { publishSelection() }
            .onChange(of: focused, initial: true) {
                if focused {
                    focusedTerm = term
                } else if focusedTerm == term {
                    // Unfocus the term _we_ marked as focused.
                    focusedTerm = nil
                }
            }
    }

    /// The editor, kept in step with the term in both directions.
    ///
    /// Split from `body` rather than chained onto it: there are enough `onChange`s between the two
    /// that the type checker gives up on a single expression.
    private var synced: some View {
        editor
            .onAppear {
                text = tinted()

                if autoFocus { focused = true }
            }
            // The term is the source of truth, but the editor is what the user types into, so each
            // side updates the other: typing writes through to the term (moving its anchors as it
            // goes), and a change made elsewhere -- an anchor added, a rename from another screen --
            // is read back in.
            .onChange(of: text) { commit() }
            .onChange(of: term.text) { reloadIfStale() }
            // An anchor added or dropped, or a different row being pointed at, changes the colours
            // over text which is otherwise untouched.
            .onChange(of: anchorSignature) { retint() }
            .onChange(of: emphasising) { retint() }
            .onChange(of: highlighting) { retint() }
            .onChange(of: tintingPrefix?.length) { retint() }
    }

    /// The term's text with its own anchors tinted, plus the borrowed prefix if there is one.
    private func tinted() -> AttributedString {
        var result = anchoredText(of: term, emphasising: emphasising, only: highlighting)

        if let tintingPrefix, tintingPrefix.length > 0 {
            let end = result.index(
                result.startIndex,
                offsetByCharacters: min(tintingPrefix.length, term.text.count)
            )

            result[result.startIndex..<end].backgroundColor = AnchorTint.background(
                tintingPrefix.color,
                emphasised: false
            )
        }

        return result
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if term.text.isEmpty {
                Text("Term")
                    .foregroundStyle(.tertiary)
                    // Matches the inset `TextEditor` gives its own text, so the placeholder sits
                    // exactly where the first typed character will.
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text, selection: $editorSelection)
                .textEditorStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                // A `TextEditor` insets its text on all four sides; undoing it lines the field up
                // with the plain fields in the rows below, vertically as well as horizontally --
                // otherwise the row is visibly taller than every other one in the form.
                .padding(.horizontal, -5)
                .padding(.vertical, -8)
                .frame(
                    maxHeight: maxLines.map { CGFloat($0) * lineHeight },
                    alignment: .topLeading
                )
                .focused($focused)
        }
        // A `TextEditor` scrolls rather than truncating, so a capped one simply ends mid-line with
        // nothing to say there is more. Left as it is for now: the row is a way in to the term's
        // own screen, where the whole text is.
        .clipped()
    }

    /// Writes what was typed back to the term, carrying its anchors along with the edit.
    private func commit() {
        let typed = String(text.characters)

        guard typed != term.text else { return }

        let previous = term.text

        term.text = typed
        term.adjustAnchors(from: previous)
        term.touch()

        // Typing does not carry the tints along -- text inserted at the edge of an anchor arrives
        // plain, and deleting can leave a tint over text no anchor covers any more -- so the
        // attributes are recomputed from the anchors the edit just moved. Only the attributes: the
        // characters are already what the user typed, and replacing them wholesale would take the
        // caret back to wherever it was before the keystroke.
        retint()
    }

    /// Reloads the editor's text from the term, unless it already says the same thing.
    ///
    /// For a change made elsewhere -- a rename from another screen, an anchor added by the row
    /// below -- where the editor is not the one holding the newer text.
    private func reloadIfStale() {
        guard String(text.characters) != term.text else { return }

        let caret = selectedOffsets()

        text = tinted()

        if let caret {
            restoreSelection(to: caret)
        }
    }

    /// Where every anchor of this term currently sits, as a value `onChange` can compare.
    ///
    /// Watching the ranges themselves rather than the link count: re-anchoring a link, or blanking
    /// a second occurrence of a word already linked, moves the tints without changing how many
    /// links there are.
    private var anchorSignature: [Int] {
        // Sorted because a relationship hands its elements back in no particular order, and a
        // signature which reshuffled on its own would repaint for no reason.
        anchoredLinks(of: term).flatMap(\.ranges)
    }

    /// Repaints the anchor tints over the text the editor already holds.
    ///
    /// The characters are left exactly as they are, so the caret does not move: only the background
    /// colours are rewritten, which is all that changes when an anchor moves under an edit.
    private func retint() {
        let repainted = tinted()

        guard repainted != text, String(repainted.characters) == String(text.characters) else {
            return
        }

        text.backgroundColor = nil

        for run in repainted.runs {
            guard let color = run.backgroundColor else { continue }

            // The two strings hold the same characters, so a range in one addresses the same text
            // in the other once it is measured in offsets both can be indexed by.
            let units = repainted.utf16
            let lower = units.distance(from: units.startIndex, to: run.range.lowerBound)
            let upper = units.distance(from: units.startIndex, to: run.range.upperBound)

            let own = text.utf16

            guard
                let start = own.index(own.startIndex, offsetBy: lower, limitedBy: own.endIndex),
                let end = own.index(own.startIndex, offsetBy: upper, limitedBy: own.endIndex)
            else { continue }

            text[start..<end].backgroundColor = color
        }
    }

    // MARK: Selection

    /// Publishes the caret to the binding the parent watches, as offsets into `term.text`.
    private func publishSelection() {
        guard let selection else { return }

        let plain = term.text

        guard
            let offsets = selectedOffsets(),
            let range = AnchorRange(lower: offsets.lowerBound, upper: offsets.upperBound)
                .caretRange(in: plain)
        else {
            selection.wrappedValue = nil
            return
        }

        selection.wrappedValue = TextSelection(range: range)
    }

    /// The current selection as UTF-16 offsets into the text.
    private func selectedOffsets() -> Range<Int>? {
        let indices = editorSelection.indices(in: text)
        let range: Range<AttributedString.Index>? =
            switch indices {
            case .insertionPoint(let index): index..<index
            case .ranges(let rangeSet): rangeSet.ranges.first
            @unknown default: nil
            }

        guard let range else { return nil }

        let units = text.utf16

        return units.distance(from: units.startIndex, to: range.lowerBound)
            ..< units.distance(from: units.startIndex, to: range.upperBound)
    }

    /// Puts the caret back at the given UTF-16 offsets, clamped to the text's length.
    private func restoreSelection(to offsets: Range<Int>) {
        let units = text.utf16
        let length = units.count

        guard
            let lower = units.index(
                units.startIndex,
                offsetBy: min(offsets.lowerBound, length),
                limitedBy: units.endIndex
            ),
            let upper = units.index(
                units.startIndex,
                offsetBy: min(offsets.upperBound, length),
                limitedBy: units.endIndex
            )
        else { return }

        editorSelection = .init(range: lower..<upper)
    }
}

extension AnchorRange {
    /// This span as a range into `text`, allowing it to be empty.
    ///
    /// ``range(in:)`` drops empty spans, since an anchor over no text has nothing to blank; a caret
    /// is exactly that and has to survive, so it is resolved a bound at a time instead.
    fileprivate func caretRange(in text: String) -> Range<String.Index>? {
        guard
            let lowerIndex = text.index(atUTF16Offset: lower),
            let upperIndex = text.index(atUTF16Offset: upper),
            lowerIndex <= upperIndex
        else { return nil }

        return lowerIndex..<upperIndex
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

import SwiftUI

/// How an anchored span is drawn: which colour, and how loudly.
///
/// The tint is what ties a blank in a term's text to the row in the "Links" section which studies
/// it, so both ends ask for the same one. Anchors rest quietly and are brought forward when their
/// row is focused, or when the caret is inside them.
enum AnchorTint {
    /// The colours anchors cycle through, in order.
    ///
    /// Arbitrary, and deliberately positional rather than derived from the target's identity: a
    /// colour per term would keep a term the same colour everywhere, at the cost of two blanks in
    /// one sentence often landing on the same one, which is the confusion that matters.
    static let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo]

    /// The colour of the anchor at `index` among a term's anchors.
    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }

    /// The background a span is drawn over. Emphasised anchors are tinted harder rather than in a
    /// different colour, so the pairing with a row stays readable while it is being pointed at.
    static func background(at index: Int, emphasised: Bool) -> Color {
        background(color(at: index), emphasised: emphasised)
    }

    /// The same tint applied to a colour already in hand, for the row quoting an anchor -- both ends
    /// of the pairing have to be tinted identically, so both come from here.
    static func background(_ color: Color, emphasised: Bool) -> Color {
        color.opacity(emphasised ? 0.42 : 0.18)
    }
}

/// A term's text with its anchored spans tinted, ready to be shown in a text field.
///
/// The anchors come from the term's links rather than from the term itself, so the ordering here is
/// the one which decides both the colours and which row each blank belongs to.
///
/// `emphasised` is the link whose anchors are drawn more strongly -- the focused row, or the one the
/// selection is sitting inside -- if any.
///
/// `only`, when given, restricts the tinting to that one link, leaving the term's other anchors
/// plain. A row showing the sentence it is anchored into wants just its own span lit: the others
/// belong to rows of their own, and colouring them here would be pointing at somebody else's blank.
/// Colours are still assigned from the term's full ordering, so a span keeps the same colour
/// wherever it is shown.
func anchoredText(
    of term: Term,
    emphasising emphasised: Link? = nil,
    only: Link? = nil
) -> AttributedString {
    var result = AttributedString(term.text)

    for (index, link) in anchoredLinks(of: term).enumerated() {
        if let only, link.persistentModelID != only.persistentModelID { continue }

        let isEmphasised = link.persistentModelID == emphasised?.persistentModelID

        for anchor in link.anchors {
            guard let range = Range(anchor, in: result) else { continue }

            result[range].backgroundColor = AnchorTint.background(
                at: index,
                emphasised: isEmphasised
            )
        }
    }

    return result
}

/// What an unfillable blank is drawn as: a run of spaces of a fixed length, tinted so it reads as a
/// rectangle. Every such blank is this wide, whatever it covers.
private let blankRun = String(repeating: "\u{2007}", count: 4)

/// A link's prompt with its own anchors replaced by what they mean, or drawn as blanks when nothing
/// says what they mean.
///
/// Substituting reads as the sentence it is -- "고양이가 학교에 [to go]" asks for the Korean word for
/// a meaning sitting in its own place, which is the question -- where a rectangle followed by a
/// translation on a line below asks the reader to carry one to the other.
///
/// Neither form keeps the width of what it covers. Blanks used to, so the sentence would not reflow
/// on reveal, but a blank as wide as what it hides tells the reader how long the answer is, which is
/// a good part of the way to knowing it -- so a substitution is as wide as the meaning it shows, and
/// a blank with nothing to show is always the same width.
func blankedPrompt(of link: Link) -> AttributedString {
    guard let text = link.source?.text else { return AttributedString() }

    let meaning = link.blankMeaning
    var result = AttributedString(text)

    // Back to front, so that replacing one anchor does not move the ones not yet replaced.
    for anchor in link.anchors.reversed() {
        guard let range = Range(anchor, in: result) else { continue }

        if meaning.isEmpty {
            // Nothing to substitute, so the words are replaced by a blank of a fixed size rather
            // than hidden in place: a rectangle as wide as what it covers says how long the answer
            // is, which is a good part of the way to saying what it is.
            var blank = AttributedString(blankRun)

            blank.foregroundColor = .clear
            blank.backgroundColor = .primary.opacity(0.12)

            result.replaceSubrange(range, with: blank)
        } else {
            // Padded with spaces rather than by a modifier: this is a run inside a string, and
            // the tint is what has to hold the room, so the space has to be characters the
            // background is drawn behind. Use non-breaking space so we don't split the blank if the
            // `meaning` starts on the next line.
            var replacement = AttributedString("\u{a0}\(meaning)\u{a0}")

            // Full strength, and not bold: the substituted meaning is the part of the sentence being
            // asked about, so it has to be as readable as the words around it, while the weight is
            // what keeps it from reading as one of them.
            replacement.foregroundColor = .primary
            replacement.font = .largeTitle.weight(.medium)
            replacement.backgroundColor = .primary.opacity(0.1)

            result.replaceSubrange(range, with: replacement)
        }
    }

    return result
}

/// What a term is otherwise studied against, shown under a blanked prompt as context.
///
/// A blank in a sentence you can read around is nearly free -- the surrounding words give it away --
/// so the translation is what turns it back into a question. Only the term's *unanchored* links
/// qualify: another blank in the same sentence is a question of its own, not context for this one.
func promptContext(of link: Link) -> [String] {
    guard let source = link.source, link.isAnchored else { return [] }

    return source.sortedOutgoingLinks
        .filter { !$0.isAnchored && $0.persistentModelID != link.persistentModelID }
        .compactMap { $0.target?.text }
}

/// The anchored links studied from `term`, in the order their anchors run through its text.
///
/// The order is what assigns the colours, so every view showing anchors reads it from here rather
/// than sorting for itself.
func anchoredLinks(of term: Term) -> [Link] {
    (term.outgoingLinks ?? [])
        .filter(\.isAnchored)
        .sorted { ($0.anchorOffsets.first?.lower ?? 0) < ($1.anchorOffsets.first?.lower ?? 0) }
}

/// The colour assigned to `link`'s anchors, or `nil` if it is not anchored.
func anchorColor(of link: Link) -> Color? {
    guard link.isAnchored, let term = link.source else { return nil }

    return anchoredLinks(of: term)
        .firstIndex { $0.persistentModelID == link.persistentModelID }
        .map { AnchorTint.color(at: $0) }
}

extension TextSelection {
    /// The selected range of `text`, or `nil` when there is no selection.
    ///
    /// Only the first range of a multi-selection: a scattered selection has no single span to blank,
    /// and taking its first is more useful than refusing outright.
    ///
    /// SwiftUI hands back indices which occasionally address the string's UTF-16 view rather than
    /// its characters, so they are converted before being used to slice it.
    func range(in text: String) -> Range<String.Index>? {
        let raw: Range<String.Index>? =
            switch indices {
            case .selection(let range): range
            case .multiSelection(let rangeSet): rangeSet.ranges.first
            @unknown default: nil
            }

        guard
            let raw,
            raw.lowerBound <= text.endIndex,
            raw.upperBound <= text.endIndex,
            let lower = String.Index(raw.lowerBound, within: text),
            let upper = String.Index(raw.upperBound, within: text),
            lower <= upper
        else { return nil }

        return lower..<upper
    }
}

/// How a selection sits relative to a term's anchors.
enum SelectionAnchoring {
    /// The selection touches nothing anchored, and covers text: it can be blanked.
    case blankable(Range<String.Index>)
    /// The selection sits inside exactly one anchor, whose link is brought forward.
    case inside(Link)
    /// The selection is empty, or spans several anchors, or partially overlaps one.
    case none

    /// The link to draw more strongly, if any.
    var emphasised: Link? {
        if case .inside(let link) = self { return link }

        return nil
    }

    /// The range which **Blank** would cover, if it is offered at all.
    var blankableRange: Range<String.Index>? {
        if case .blankable(let range) = self { return range }

        return nil
    }
}

/// Reads what `selection` means for `term`'s anchors.
///
/// A selection overlapping an existing anchor cannot be blanked -- even partially -- since anchors
/// do not nest and a partial overlap has no sensible reading. One sitting wholly inside a single
/// anchor is instead taken as pointing at it, which is what highlights the matching row. A caret
/// (an empty selection) selects no text, so there is nothing to blank and nothing to point at
/// unless it is strictly inside an anchor.
func anchoring(of selection: TextSelection?, in term: Term) -> SelectionAnchoring {
    guard let range = selection?.range(in: term.text) else { return .none }

    /// Whether the selection sits wholly within `anchor`, which is what makes it point at that one
    /// rather than merely touch it.
    func contains(_ anchor: Range<String.Index>) -> Bool {
        anchor.lowerBound <= range.lowerBound && range.upperBound <= anchor.upperBound
    }

    var touched: [Link] = []
    var containedBy: Link?

    for link in anchoredLinks(of: term) {
        for anchor in link.anchors where anchor.overlaps(range) {
            touched.append(link)

            if contains(anchor) {
                containedBy = link
            }
        }
    }

    // Inside exactly one anchor: pointing at it, not blanking it.
    if touched.count == 1, let link = containedBy {
        return .inside(link)
    }

    // Touching any anchor at all rules out blanking -- anchors do not nest, and a partial overlap
    // has no reading. So does an empty selection, which covers no text to blank.
    guard touched.isEmpty, !range.isEmpty else { return .none }

    return .blankable(range)
}

extension Range where Bound == String.Index {
    /// Whether this range and `other` share any text, counting a caret sitting strictly inside.
    fileprivate func overlaps(_ other: Range<String.Index>) -> Bool {
        if other.isEmpty {
            return lowerBound < other.lowerBound && other.lowerBound < upperBound
        }

        return lowerBound < other.upperBound && other.lowerBound < upperBound
    }
}

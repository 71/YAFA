import Foundation
import SwiftData

/// A directed edge between two ``Term``s: study `source`, grade recall of `target`.
///
/// A link is the pair of a prompt and an answer, plus the ``Progress`` it is scheduled against.
/// Progress is not necessarily its own: two links may share one, in which case reviewing either
/// advances the schedule of both.
///
/// The reverse direction is a different link, which may share the same ``Progress``.
///
/// A link may be *anchored*: it records where its target appears in `source.text`, and is studied by
/// showing that text with the anchored spans blanked out. An unanchored link shows the whole text.
@Model
final class Link {
    var source: Term?
    var target: Term?

    /// Nullify rather than cascade: a progress may be shared, and deleting one of its links must
    /// not take the other sharers' schedule and history with it. `deleteProgressIfOrphaned()`
    /// cleans up the progress when the last sharer goes away.
    @Relationship(deleteRule: .nullify, inverse: \Progress.links)
    var progress: Progress?

    /// Reviews which recorded *this* link as what was shown. Only needed as the inverse of
    /// `Review.link`, which CloudKit requires; the history itself is read from the progress.
    @Relationship(inverse: \Review.link)
    private(set) var reviews: [Review]?

    private(set) var creationDate: Date = Date(timeIntervalSince1970: .zero)

    /// Free text shown with the prompt, ahead of the answer, to narrow a guess this link's source
    /// cannot narrow on its own.
    ///
    /// A term with several outgoing links can lean on its ``siblings`` instead, but the first
    /// ambiguous link has none: 차 → car is just "car" until 차 → tea exists. Empty when unset.
    var hint: String = ""

    /// Where `target` appears in `source.text`, as a flat list of alternating lower/upper UTF-16
    /// offsets. Empty for an ordinary link, which is studied by showing the whole text.
    ///
    /// Flat rather than an array of ranges because SwiftData stores this as a plain attribute, and
    /// `[Int]` is one it can hold as-is. ``anchors`` is the shape everything else works in.
    private(set) var ranges: [Int] = []

    init(
        source: Term,
        target: Term,
        progress: Progress? = nil,
        creationDate: Date = .now,
        ranges: [Int] = []
    ) {
        self.source = source
        self.target = target
        self.progress = progress ?? Progress(creationDate: creationDate)
        self.creationDate = creationDate
        self.ranges = ranges
    }

    /// The link studying the same two terms the other way around, if it exists.
    var reverse: Link? {
        guard let source, let target else { return nil }

        return (target.outgoingLinks ?? []).first { $0.target?.persistentModelID == source.persistentModelID }
    }

    /// Whether `other` studies the same two terms in the opposite direction.
    func isReverse(of other: Link) -> Bool {
        guard
            let source, let target, let otherSource = other.source, let otherTarget = other.target
        else { return false }

        return source.persistentModelID == otherTarget.persistentModelID
            && target.persistentModelID == otherSource.persistentModelID
    }

    /// Swaps which term prompts and which is recalled, keeping the schedule.
    ///
    /// An anchor points into the old source's text, which is no longer what is shown, so it does not
    /// survive the swap.
    func swapDirection() {
        let oldSource = source

        source = target
        target = oldSource
        ranges = []
    }

    /// Adds the reverse link, sharing this one's progress, and returns it.
    ///
    /// Sharing rather than starting fresh is the point: the two directions are the same piece of
    /// knowledge, so recalling one is evidence about the other.
    @discardableResult
    func addReverse() -> Link? {
        guard let source, let target, reverse == nil else { return reverse }

        let link = Link(source: target, target: source, progress: progress)

        modelContext?.insert(link)

        return link
    }

    // MARK: Anchoring

    /// Whether this link points at a span of its source's text rather than at the text as a whole.
    var isAnchored: Bool { !ranges.isEmpty }

    /// The anchored spans, as ranges into `source.text`.
    ///
    /// Offsets which no longer address the text -- the store and the text disagreeing after a sync,
    /// say -- are dropped rather than trusted, since a bad range would read as a blank over the
    /// wrong words.
    var anchors: [Range<String.Index>] {
        guard let text = source?.text else { return [] }

        return anchorOffsets.compactMap { $0.range(in: text) }
    }

    /// The anchored spans as UTF-16 offset pairs, in the order they appear in the text.
    var anchorOffsets: [AnchorRange] {
        AnchorRange.unpack(ranges)
    }

    /// Anchors this link over `newAnchors`, which are ranges into `source.text`.
    ///
    /// Overlapping and empty ranges are dropped: an anchor covering no text has nothing to blank,
    /// and two anchors over the same span would blank it twice.
    func anchor(over newAnchors: [Range<String.Index>]) {
        guard let text = source?.text else { return }

        ranges = AnchorRange.pack(newAnchors.map { AnchorRange($0, in: text) })
    }

    /// Drops the anchors, leaving an ordinary link to the same term.
    ///
    /// The link, its progress and its review history are untouched: unanchoring changes what is
    /// shown, not what is scheduled.
    func unanchor() {
        ranges = []
    }

    /// Moves the anchors to follow an edit of the source's text, and reports whether any changed.
    ///
    /// See ``TextEdit`` for how the edit is recovered and ``AnchorRange/adjusted(for:)`` for what
    /// happens to each anchor.
    @discardableResult
    func adjustAnchors(for edit: TextEdit) -> Bool {
        guard isAnchored else { return false }

        let adjusted = AnchorRange.pack(anchorOffsets.compactMap { $0.adjusted(for: edit) })

        guard adjusted != ranges else { return false }

        ranges = adjusted

        return true
    }

    // MARK: Studying

    /// The text shown before the answer is revealed: the source's text, with this link's own
    /// anchors -- and only its own -- replaced by a placeholder.
    ///
    /// The prompt a reader actually sees draws its blanks as rectangles rather than spelling them
    /// out; see `blankedPrompt(of:)`. This is the flattened form, for sorting and for the rows which
    /// need a plain string.
    var promptText: String {
        guard let text = source?.text else { return "" }

        let anchors = self.anchors

        guard !anchors.isEmpty else { return text }

        var prompt = ""
        var index = text.startIndex

        for anchor in anchors {
            prompt += text[index..<anchor.lowerBound]
            prompt += Self.blankPlaceholder
            index = anchor.upperBound
        }

        return prompt + text[index...]
    }

    /// The text revealed as the answer.
    var answerText: String { target?.text ?? "" }

    /// The other links studied from the same source, offered during study as answers this prompt
    /// could equally have wanted.
    ///
    /// Recalling "tea" when 차 → car came up is a right answer to the wrong link; listing the
    /// siblings is what lets it be graded as one. Anchored siblings are left out: their targets
    /// answer a different blank in the same sentence, not this one.
    ///
    /// An anchored link has none. Its unanchored siblings are the sentence's translation, which the
    /// prompt already shows as context -- the blank would give itself away without it -- so listing
    /// them again would print the same words twice, once as the question and once as an answer to
    /// grade.
    var siblings: [Link] {
        guard let source, !isAnchored else { return [] }

        return source.sortedOutgoingLinks
            .filter { $0.persistentModelID != persistentModelID && !$0.isAnchored }
    }

    /// What the blank stands for, shown in place of the hidden words when this link is studied.
    ///
    /// The link itself points at a term in the same language -- 갔다 at 가다 -- so what the blank
    /// *means* is a hop further out: the targets of the target's own unanchored links. The hint wins
    /// when there is one, since it was written for this blank where the hop is merely derived, and
    /// several translations are listed rather than one being picked.
    ///
    /// Empty when neither is available, which leaves the blank as a plain rectangle.
    var blankMeaning: String {
        guard !hint.isEmpty else {
            // Sorted rather than as the relationship hands them back, which is in no order at all:
            // a blank whose translations swap places between two reviews reads as a different
            // question each time.
            let translations = (target?.sortedOutgoingLinks ?? [])
                .filter { !$0.isAnchored }
                .compactMap { $0.target?.text }
                .filter { !$0.isEmpty }

            return translations.joined(separator: ", ")
        }

        return hint
    }

    /// The term whose view this link is listed under.
    var owningTerm: Term? { source }

    /// Whether either end of this link carries one of `tags`.
    ///
    /// Both ends, not just the source: tags belong to terms, and a link joins two of them, so
    /// tagging either is a statement that this piece of knowledge is part of that group. Which end
    /// happens to be the prompt is a separate question, and one the reader can change -- reversing
    /// a link used to move it out of the group it was tagged into, because the tag was on the term
    /// which had just become the answer.
    func joins(tagIn tags: Set<Tag>) -> Bool {
        source?.has(tagIn: tags) == true || target?.has(tagIn: tags) == true
    }

    /// What an anchored span is written as when the prompt has to be a plain string.
    ///
    /// Only for the places which cannot draw -- sorting, export, a compact row. The prompt itself
    /// substitutes what the blank means, or draws a rectangle when nothing says what it means; see
    /// `blankedPrompt(of:)`.
    static let blankPlaceholder = "____"

    // MARK: Progress

    var nextReviewDate: Date {
        progress?.nextReviewDate ?? .distantPast
    }

    func isDoneForNow(now: Date) -> Bool {
        nextReviewDate.timeIntervalSince(now) > 0
    }

    /// The date of the last review of *this* link, which may be older than the last review of its
    /// progress if the progress is shared.
    var lastReviewDate: Date? {
        progress?.reviews?
            .lazy
            .filter { $0.link?.persistentModelID == self.persistentModelID }
            .map(\.date)
            .max()
    }

    @discardableResult
    func addReview(outcome: Review.Outcome) -> ReviewUndo? {
        progress?.addReview(of: self, outcome: outcome)
    }

    /// Schedules this link against `progress`, dropping the one it used to have if that leaves
    /// nothing pointing at it.
    ///
    /// The old progress is released *after* the reassignment and only once it has no sharers left:
    /// dropping it up front would cascade to a review history other sharers may still need.
    func join(progress: Progress) {
        let previous = self.progress

        guard previous?.persistentModelID != progress.persistentModelID else { return }

        self.progress = progress

        if let previous, previous.sharers.isEmpty {
            modelContext?.delete(previous)
        }
    }

    /// Gives this link a progress of its own, abandoning whatever it shared before.
    ///
    /// The schedule is carried over so that leaving a set doesn't reset what was already learned,
    /// but the review history stays with the set: those reviews happened to the others too.
    func leaveSharedProgress() {
        guard let previous = progress, previous.sharers.count > 1 else { return }

        let own = Progress()

        own.reschedule(to: previous.nextReviewDate)
        own.fsrsCard = previous.fsrsCard

        modelContext?.insert(own)
        progress = own
    }

    /// Deletes this link, along with its progress if nothing else was sharing it.
    ///
    /// Progress is nullified rather than cascaded on delete, so that a shared progress survives
    /// losing one of its sharers; this drops it once the last one goes.
    func delete() {
        let context = modelContext

        // Decide before deleting: afterwards the relationship no longer reliably reports who was
        // sharing the progress.
        let progressToDelete = progress.flatMap { progress in
            progress.sharers.allSatisfy { $0.persistentModelID == persistentModelID }
                ? progress : nil
        }

        context?.delete(self)

        if let progressToDelete {
            context?.delete(progressToDelete)
        }
    }
}

/// One anchored span, as the UTF-16 offsets it is stored as.
///
/// UTF-16 because that is what `TextSelection` and `AttributedString` speak, and because a
/// `String.Index` is meaningless once the string it indexes has been let go of. Everything which
/// crosses into the model does so as offsets; everything above it works in `String.Index`.
struct AnchorRange: Equatable, Hashable {
    var lower: Int
    var upper: Int

    init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }

    init(_ range: Range<String.Index>, in text: String) {
        let utf16 = text.utf16

        self.lower = utf16.distance(from: utf16.startIndex, to: range.lowerBound)
        self.upper = utf16.distance(from: utf16.startIndex, to: range.upperBound)
    }

    /// Whether this span covers no text, or could not address any: a span reaching below the start
    /// of the string is as meaningless as one whose bounds are the wrong way round.
    ///
    /// Checked rather than assumed because the offsets come off disk, where a sync from another
    /// device -- or an older build -- can put anything in them.
    var isEmpty: Bool { lower >= upper || lower < 0 }

    /// This span as a range into `text`, or `nil` if it does not address it.
    ///
    /// An offset landing inside a character -- half of a surrogate pair, or the middle of a
    /// grapheme cluster -- has no `String.Index`, so such a span is dropped rather than rounded to
    /// something the user did not select.
    func range(in text: String) -> Range<String.Index>? {
        guard
            lower < upper,
            let lowerIndex = text.index(atUTF16Offset: lower),
            let upperIndex = text.index(atUTF16Offset: upper)
        else { return nil }

        return lowerIndex..<upperIndex
    }

    /// Where this span sits once `edit` has been applied, or `nil` if nothing of it survived.
    ///
    /// A span entirely before the edit does not move; one entirely after shifts by the edit's
    /// delta; one containing or overlapping the edit is clipped to whatever the edit left behind,
    /// growing or shrinking with it. Clipping keeps the anchor over the text which survived --
    /// fixing a typo or reconjugating a word should not cost the anchor -- and only an edit which
    /// removes the span outright leaves nothing to keep.
    func adjusted(for edit: TextEdit) -> AnchorRange? {
        // Wholly before the replaced range, and not merely touching it: an insertion at the
        // anchor's upper bound extends the anchor rather than sitting after it, which is what makes
        // typing at the end of a blanked word keep it blanked. The two edges are deliberately not
        // symmetric -- an insertion at the *lower* bound pushes the anchor along instead -- because
        // text typed in front of a blank reads as part of the sentence around it, where text typed
        // at the end of a word reads as part of the word.
        if upper < edit.replaced.lowerBound
            || (upper == edit.replaced.lowerBound && !edit.isInsertionPoint)
        {
            return self
        }

        // Wholly after: everything shifts by however much longer or shorter the text got.
        if lower >= edit.replaced.upperBound {
            return .init(lower: lower + edit.delta, upper: upper + edit.delta)
        }

        // Overlapping. What is kept is the part before the edit, plus the part after it -- shifted
        // -- plus, when the edit falls strictly inside the anchor, the text which replaced it.
        let newLower = Swift.min(lower, edit.replaced.lowerBound)
        let tailLength = Swift.max(0, upper - edit.replaced.upperBound)
        let insideLength =
            lower <= edit.replaced.lowerBound && upper >= edit.replaced.upperBound
            ? edit.insertedLength : 0
        let newUpper = Swift.max(newLower, edit.replaced.lowerBound) + insideLength + tailLength

        guard newLower < newUpper else { return nil }

        return .init(lower: newLower, upper: newUpper)
    }

    /// Reads the flat storage form back into spans, in order and without overlaps.
    static func unpack(_ ranges: [Int]) -> [AnchorRange] {
        var result: [AnchorRange] = []

        for index in stride(from: 0, to: ranges.count - 1, by: 2) {
            result.append(.init(lower: ranges[index], upper: ranges[index + 1]))
        }

        return normalized(result)
    }

    /// Writes spans into the flat storage form, in order and without overlaps.
    static func pack(_ anchors: [AnchorRange]) -> [Int] {
        normalized(anchors).flatMap { [$0.lower, $0.upper] }
    }

    /// Drops empty spans and merges overlapping ones, leaving them ordered by position.
    ///
    /// Overlaps have no meaning -- a span of text is either blanked or it is not -- and letting two
    /// through would blank the shared part twice.
    private static func normalized(_ anchors: [AnchorRange]) -> [AnchorRange] {
        var result: [AnchorRange] = []

        for anchor in anchors.filter({ !$0.isEmpty }).sorted(by: { $0.lower < $1.lower }) {
            if var last = result.last, last.upper >= anchor.lower {
                last.upper = Swift.max(last.upper, anchor.upper)
                result[result.count - 1] = last
            } else {
                result.append(anchor)
            }
        }

        return result
    }
}

extension String {
    /// The index `offset` UTF-16 units into this string, or `nil` if that lands past its end or
    /// inside a character.
    func index(atUTF16Offset offset: Int) -> String.Index? {
        guard
            offset >= 0,
            let index = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex)
        else { return nil }

        return String.Index(index, within: self)
    }
}

/// A single contiguous edit of a string, in UTF-16 offsets.
///
/// SwiftUI reports text after the fact, so the edit is recovered by comparing what the text was
/// with what it became. That is exact for one contiguous change, which is what typing, pasting, and
/// deleting a selection all produce; a scattered multi-cursor edit or a wholesale replacement is
/// reported as one large range covering everything which differs, which is the right answer for the
/// anchors even when it is not the literal keystroke.
struct TextEdit: Equatable {
    /// The range of the *old* text which was replaced.
    let replaced: Range<Int>
    /// How many UTF-16 units replaced it.
    let insertedLength: Int

    /// How much longer (or shorter) the text got.
    var delta: Int { insertedLength - (replaced.upperBound - replaced.lowerBound) }

    /// Whether this is a pure insertion, replacing nothing.
    var isInsertionPoint: Bool { replaced.isEmpty }

    /// Recovers the edit turning `old` into `new`, or `nil` if they are the same text.
    ///
    /// The common prefix and the common suffix bound what changed; everything between them is taken
    /// as replaced. The two runs are not allowed to overlap, so a repeated character typed into a
    /// run of the same character resolves to a single insertion rather than a negative range.
    init?(from old: String, to new: String) {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)

        guard oldUnits != newUnits else { return nil }

        var prefix = 0

        while prefix < oldUnits.count, prefix < newUnits.count, oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }

        var suffix = 0

        while
            suffix < oldUnits.count - prefix,
            suffix < newUnits.count - prefix,
            oldUnits[oldUnits.count - 1 - suffix] == newUnits[newUnits.count - 1 - suffix]
        {
            suffix += 1
        }

        self.replaced = prefix..<(oldUnits.count - suffix)
        self.insertedLength = newUnits.count - suffix - prefix
    }
}

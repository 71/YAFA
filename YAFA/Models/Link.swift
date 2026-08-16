import Foundation
import SwiftData

/// Something which can be studied: a ``Link`` or a ``ClozeBlank``.
///
/// A studiable is the pair of a prompt and an answer, plus the ``Progress`` it is scheduled
/// against. Progress is not necessarily its own: two studiables may share one, in which case
/// reviewing either advances the schedule of both.
protocol Studiable: PersistentModel {
    /// The text shown before the answer is revealed.
    var promptText: String { get }
    /// The text revealed as the answer.
    var answerText: String { get }

    /// The scheduling state this studiable is graded against.
    var progress: Progress? { get }

    /// The term whose view this studiable is listed under.
    var owningTerm: Term? { get }

    /// Records this studiable as the subject of `review`.
    func attach(review: Review)
}

extension Studiable {
    var nextReviewDate: Date {
        progress?.nextReviewDate ?? .distantPast
    }

    func isDoneForNow(now: Date) -> Bool {
        nextReviewDate.timeIntervalSince(now) > 0
    }

    /// The date of the last review of *this* studiable, which may be older than the last review of
    /// its progress if the progress is shared.
    var lastReviewDate: Date? {
        progress?.reviews?
            .lazy
            .filter { $0.studied?.persistentModelID == self.persistentModelID }
            .map(\.date)
            .max()
    }

    @discardableResult
    func addReview(outcome: Review.Outcome) -> ReviewUndo? {
        progress?.addReview(of: self, outcome: outcome)
    }

    /// Schedules this studiable against `progress`, dropping the one it used to have if that
    /// leaves nothing pointing at it.
    ///
    /// The old progress is released *after* the reassignment and only once it has no sharers left:
    /// dropping it up front would cascade to a review history other sharers may still need.
    func join(progress: Progress) {
        let previous = self.progress

        guard previous?.persistentModelID != progress.persistentModelID else { return }

        set(progress: progress)

        if let previous, previous.sharers.isEmpty {
            modelContext?.delete(previous)
        }
    }

    /// Gives this studiable a progress of its own, abandoning whatever it shared before.
    ///
    /// The schedule is carried over so that leaving a set doesn't reset what was already learned,
    /// but the review history stays with the set: those reviews happened to the others too.
    func leaveSharedProgress() {
        guard let previous = progress, previous.sharers.count > 1 else { return }

        let own = Progress()

        own.reschedule(to: previous.nextReviewDate)
        own.fsrsCard = previous.fsrsCard

        modelContext?.insert(own)
        set(progress: own)
    }

    private func set(progress: Progress) {
        if let link = self as? Link {
            link.progress = progress
        } else if let blank = self as? ClozeBlank {
            blank.progress = progress
        }
    }

    /// Deletes this studiable, along with its progress if nothing else was sharing it.
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

/// A directed edge between two ``Term``s: study `source`, grade recall of `target`.
///
/// The reverse direction is a different link, which may share the same ``Progress``.
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

    init(source: Term, target: Term, progress: Progress? = nil, creationDate: Date = .now) {
        self.source = source
        self.target = target
        self.progress = progress ?? Progress(creationDate: creationDate)
        self.creationDate = creationDate
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
    func swapDirection() {
        let oldSource = source

        source = target
        target = oldSource
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
}

extension Link: Studiable {
    var promptText: String { source?.text ?? "" }
    var answerText: String { target?.text ?? "" }
    var owningTerm: Term? { source }

    func attach(review: Review) {
        review.link = self
    }
}

/// A sentence with one or more numbered blanks, each answered by a ``Term``.
///
/// Unlike a ``Link``, a cloze has no source term: the sentence itself is the prompt.
@Model
final class Cloze {
    /// The full sentence, as ordinary text and without placeholders.
    ///
    /// Blanks point at ranges of this string rather than owning rendered strings of their own, so
    /// the sentence always stays readable as-is, and a blank can never disagree with the term it
    /// points to.
    var template: String = ""
    var notes: String = ""

    private(set) var creationDate: Date = Date(timeIntervalSince1970: .zero)

    @Relationship(inverse: \Tag.clozes)
    var tags: [Tag]?

    @Relationship(deleteRule: .cascade, inverse: \ClozeBlank.cloze)
    private(set) var blanks: [ClozeBlank]?

    init(template: String = "", notes: String = "", creationDate: Date = .now, tags: [Tag] = []) {
        self.template = template
        self.notes = notes
        self.creationDate = creationDate
        self.tags = tags
        self.blanks = []
    }

    /// Blanks in the order they appear in `template`.
    var orderedBlanks: [ClozeBlank] {
        (blanks ?? []).sorted { ($0.offsets.first ?? 0) < ($1.offsets.first ?? 0) }
    }

    @discardableResult
    func addBlank(term: Term, ranges: [Range<String.Index>]) -> ClozeBlank {
        let blank = ClozeBlank(cloze: self, term: term, ranges: ranges, in: template)

        modelContext?.insert(blank)

        if blanks == nil {
            blanks = [blank]
        } else {
            blanks!.append(blank)
        }

        return blank
    }
}

/// One blank of a ``Cloze``: the term shown as the answer when that blank is hidden.
///
/// Studying a blank shows the cloze's `template` with the blank's range(s) hidden and everything
/// else shown as-is.
@Model
final class ClozeBlank {
    var cloze: Cloze?
    var term: Term?

    /// Ranges of `cloze.template` covered by this blank, stored as a flat list of alternating
    /// lower/upper UTF-16 offsets since `Range<String.Index>` is not persistable.
    private(set) var offsets: [Int] = []

    /// See `Link.progress`.
    @Relationship(deleteRule: .nullify, inverse: \Progress.clozeBlanks)
    var progress: Progress?

    /// See `Link.reviews`.
    @Relationship(inverse: \Review.clozeBlank)
    private(set) var reviews: [Review]?

    init(
        cloze: Cloze,
        term: Term,
        ranges: [Range<String.Index>],
        in template: String,
        progress: Progress? = nil,
        creationDate: Date = .now
    ) {
        self.cloze = cloze
        self.term = term
        self.progress = progress ?? Progress(creationDate: creationDate)
        self.setRanges(ranges, in: template)
    }

    /// The ranges of `template` this blank covers, in order.
    func ranges(in template: String) -> [Range<String.Index>] {
        stride(from: 0, to: offsets.count - 1, by: 2).compactMap { i in
            guard
                let lower = String.Index(
                    template.utf16.index(
                        template.utf16.startIndex,
                        offsetBy: offsets[i],
                        limitedBy: template.utf16.endIndex
                    ) ?? template.utf16.endIndex,
                    within: template
                ),
                let upper = String.Index(
                    template.utf16.index(
                        template.utf16.startIndex,
                        offsetBy: offsets[i + 1],
                        limitedBy: template.utf16.endIndex
                    ) ?? template.utf16.endIndex,
                    within: template
                ),
                lower <= upper
            else { return nil }

            return lower..<upper
        }
    }

    func setRanges(_ ranges: [Range<String.Index>], in template: String) {
        offsets = ranges.sorted { $0.lowerBound < $1.lowerBound }.flatMap { range in
            [
                template.utf16.distance(from: template.utf16.startIndex, to: range.lowerBound),
                template.utf16.distance(from: template.utf16.startIndex, to: range.upperBound),
            ]
        }
    }

    /// The number of the blank within its cloze, starting at 1.
    var number: Int {
        (cloze?.orderedBlanks.firstIndex(of: self) ?? 0) + 1
    }
}

extension ClozeBlank: Studiable {
    /// The template with this blank's ranges replaced by a placeholder, and every other blank left
    /// filled in.
    var promptText: String {
        guard let template = cloze?.template else { return "" }

        var result = ""
        var index = template.startIndex

        for range in ranges(in: template) {
            guard range.lowerBound >= index else { continue }

            result.append(contentsOf: template[index..<range.lowerBound])
            result.append(clozePlaceholder)
            index = range.upperBound
        }

        result.append(contentsOf: template[index...])

        return result
    }

    var answerText: String { term?.text ?? "" }
    var owningTerm: Term? { term }

    func attach(review: Review) {
        review.clozeBlank = self
    }
}

/// Shown in place of a hidden cloze blank.
let clozePlaceholder = "(...)"

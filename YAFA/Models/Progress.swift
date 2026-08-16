import FSRS
import Foundation
import SwiftData

/// The FSRS state and review history something is scheduled against.
///
/// Links and cloze blanks each get their own progress when created, but two or more can be pointed
/// at the same one, so that reviewing any of them advances scheduling for all of them (e.g. EN→KO
/// and KO→EN for the same term).
@Model
final class Progress {
    var fsrsCard: Card = Card()

    /// The date at which the progress' next review is due.
    ///
    /// Duplicates `fsrsCard.due`, which cannot be sorted on or used in a `#Predicate` since
    /// `fsrsCard` is stored as an opaque blob.
    var nextReviewDate: Date = Date(timeIntervalSince1970: .zero)

    @Relationship(deleteRule: .cascade, inverse: \Review.progress)
    private(set) var reviews: [Review]?

    /// Links scheduled against this progress.
    private(set) var links: [Link]?
    /// Cloze blanks scheduled against this progress.
    private(set) var clozeBlanks: [ClozeBlank]?

    init(creationDate: Date = .now) {
        self.fsrsCard = .init(due: creationDate)
        self.nextReviewDate = creationDate
        self.reviews = []
    }

    /// Everything scheduled against this progress.
    var sharers: [any Studiable] {
        (links ?? []) as [any Studiable] + (clozeBlanks ?? []) as [any Studiable]
    }

    /// Sharers gathered into what reads as a single entry: a link and its reverse together, or a
    /// lone link or cloze blank on its own.
    ///
    /// A mutual pair keeps both of its sharers -- each direction is studied and removed separately
    /// -- but they belong under one arrow, so the grouping is done here rather than by hunting for
    /// adjacency in the view.
    var sharerGroups: [SharerGroup] {
        let ordered = sortedSharers
        var groups: [SharerGroup] = []
        var placed = Set<PersistentIdentifier>()

        for sharer in ordered where !placed.contains(sharer.persistentModelID) {
            placed.insert(sharer.persistentModelID)

            guard let link = sharer as? Link else {
                groups.append(.init(sharers: [sharer]))
                continue
            }

            let reverse = ordered.first { other in
                guard
                    !placed.contains(other.persistentModelID),
                    let other = other as? Link
                else { return false }

                return link.isReverse(of: other)
            }

            if let reverse {
                placed.insert(reverse.persistentModelID)
                groups.append(.init(sharers: [link, reverse]))
            } else {
                groups.append(.init(sharers: [link]))
            }
        }

        return groups
    }

    /// Sharers ordered so that a link and its reverse are adjacent, which is what lets the two
    /// directions of one pair of terms be shown as a pair rather than two unrelated rows.
    var sortedSharers: [any Studiable] {
        let links = (self.links ?? []).sorted {
            $0.promptText.localizedCaseInsensitiveCompare($1.promptText) == .orderedAscending
        }

        var result: [any Studiable] = []
        var placed = Set<PersistentIdentifier>()

        for link in links where !placed.contains(link.persistentModelID) {
            result.append(link)
            placed.insert(link.persistentModelID)

            // Pull the reverse up next to it, if it is in this set too.
            if let reverse = links.first(where: {
                !placed.contains($0.persistentModelID) && link.isReverse(of: $0)
            }) {
                result.append(reverse)
                placed.insert(reverse.persistentModelID)
            }
        }

        return result + (clozeBlanks ?? []) as [any Studiable]
    }

    var lastReviewDate: Date? {
        reviews?.lazy.map(\.date).max()
    }

    /// Reviews from newest to oldest.
    var reviewsByDate: [Review] {
        (reviews ?? []).sorted { $0.date > $1.date }
    }

    func isDoneForNow(now: Date) -> Bool {
        nextReviewDate.timeIntervalSince(now) > 0
    }

    /// Moves the next review to `date`, keeping the FSRS card's own due date in step.
    func reschedule(to date: Date) {
        nextReviewDate = date
        fsrsCard.due = date
    }

    /// Returns the sharer to show for the next review: whichever hasn't been studied the longest.
    ///
    /// This is deterministic rather than random, so two sharers alternate exactly instead of merely
    /// tending to -- picking randomly, even weighted by staleness, would let the same sharer come up
    /// twice in a row.
    var nextSharer: (any Studiable)? {
        let sharers = self.sharers

        guard sharers.count > 1 else { return sharers.first }

        // Order by date rather than by position in `reviews`: a to-many relationship makes no
        // promise about the order it hands its elements back in.
        var lastReviewById = [PersistentIdentifier: Date]()

        for review in reviews ?? [] {
            guard let studied = review.studied else { continue }

            let id = studied.persistentModelID

            if lastReviewById[id].map({ $0 < review.date }) ?? true {
                lastReviewById[id] = review.date
            }
        }

        // A sharer which was never studied comes first, then the least recently studied one. Ties
        // are broken by identity so that the choice stays stable rather than depending on the order
        // `sharers` happens to come back in.
        return sharers.min { a, b in
            switch (lastReviewById[a.persistentModelID], lastReviewById[b.persistentModelID]) {
            case (nil, nil): a.persistentModelID.hashValue < b.persistentModelID.hashValue
            case (nil, _): true
            case (_, nil): false
            case (let dateA?, let dateB?):
                dateA == dateB
                    ? a.persistentModelID.hashValue < b.persistentModelID.hashValue
                    : dateA < dateB
            }
        }
    }

    /// Grades `studied` and advances this progress' schedule accordingly.
    @discardableResult
    func addReview(of studied: some Studiable, outcome: Review.Outcome) -> ReviewUndo {
        let now = Date.now
        let review = Review(progress: self, date: now, outcome: outcome)

        studied.attach(review: review)

        if reviews == nil {
            reviews = [review]
        } else {
            reviews!.append(review)
        }

        let fsrs = FSRS(parameters: .init())
        let grade: Rating =
            switch outcome {
            case .ok: .good
            case .fail: .again
            case .easy: .easy
            case .hard: .hard
            }

        let undo = ReviewUndo(
            review: review,
            previousCard: fsrsCard,
            previousDue: nextReviewDate
        )

        fsrsCard = try! fsrs.next(card: fsrsCard, now: now, grade: grade).card
        nextReviewDate = fsrsCard.due

        return undo
    }

    /// Appends a review which already happened, without touching the FSRS schedule.
    ///
    /// Used when migrating an existing history onto a new progress, where the FSRS card is carried
    /// over wholesale rather than replayed.
    func record(
        review date: Date,
        outcome: Review.Outcome,
        of studied: some Studiable,
        in context: ModelContext
    ) {
        let review = Review(progress: self, date: date, outcome: outcome)

        studied.attach(review: review)
        context.insert(review)

        if reviews == nil {
            reviews = [review]
        } else {
            reviews!.append(review)
        }
    }

    fileprivate func undoReview(_ undo: ReviewUndo) {
        guard let reviewIndex = reviews?.lastIndex(of: undo.review) else { return }

        reviews!.remove(at: reviewIndex)
        modelContext?.delete(undo.review)
        nextReviewDate = undo.previousDue
        fsrsCard = undo.previousCard
    }
}

/// One entry of a progress' link list: either a single link or cloze blank, or the two directions
/// of one pair of terms.
struct SharerGroup: Identifiable {
    let sharers: [any Studiable]

    var id: PersistentIdentifier { sharers[0].persistentModelID }

    /// Whether this is a pair of links studying the same two terms both ways.
    var isMutual: Bool { sharers.count > 1 }
}

struct ReviewUndo {
    let review: Review
    let previousCard: Card
    let previousDue: Date

    func undo() {
        review.progress?.undoReview(self)
    }
}

/// A single grading of a ``Link`` or ``ClozeBlank``.
@Model
final class Review {
    enum Outcome: Int, Codable, CustomStringConvertible {
        case ok, fail, easy, hard

        var description: String {
            switch self {
            case .ok: "ok"
            case .fail: "fail"
            case .easy: "easy"
            case .hard: "hard"
            }
        }
    }

    /// What was actually shown for this review.
    ///
    /// A review records this rather than only the progress it belongs to, because once a progress
    /// is shared, the reviews inside it can come from different links or cloze blanks. The two
    /// relationships stand in for an enum, which SwiftData cannot store; at most one is set.
    var link: Link?
    var clozeBlank: ClozeBlank?

    var progress: Progress?

    private(set) var date: Date = Date(timeIntervalSince1970: .zero)
    private(set) var outcome: Outcome = Outcome.ok

    fileprivate init(progress: Progress, date: Date, outcome: Outcome) {
        self.progress = progress
        self.date = date
        self.outcome = outcome
    }

    /// The link or cloze blank which was studied, if it still exists.
    var studied: (any Studiable)? {
        link ?? clozeBlank
    }
}

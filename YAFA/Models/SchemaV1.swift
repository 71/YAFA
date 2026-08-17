import FSRS
import Foundation
import SwiftData

/// The schema as it was before terms and links were introduced.
///
/// This is a *retroactive* snapshot: it describes what is already on disk, so that SwiftData has
/// something named and versioned to migrate _from_. Nothing here should ever change again; the
/// models are only ever read, by `YAFAMigrationPlan`.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Flashcard.self, FlashcardReview.self, FlashcardTag.self]
    }

    enum StudyMode: String, Codable {
        case recallBack, recallFront, recallBothSides
    }

    @Model
    final class Flashcard {
        var front: String = ""
        var back: String = ""
        var notes: String = ""

        var creationDate: Date = Date(timeIntervalSince1970: .zero)
        var modificationDate: Date = Date(timeIntervalSince1970: .zero)
        var nextReviewDate: Date = Date(timeIntervalSince1970: .zero)

        var fsrsCard: Card = Card()

        @Relationship(inverse: \FlashcardTag.flashcards)
        var tags: [FlashcardTag]?
        @Relationship(deleteRule: .cascade, inverse: \FlashcardReview.flashcard)
        var reviews: [FlashcardReview]?

        init() {}

        /// The study mode inherited from the flashcard's tags, if any of them is being studied.
        var studyMode: StudyMode? {
            var result: StudyMode?

            for tag in tags ?? [] {
                switch tag.studyMode {
                case nil: break
                case .recallBothSides: return .recallBothSides

                case .recallBack:
                    if result == .recallFront { return .recallBothSides }
                    result = .recallBack

                case .recallFront:
                    if result == .recallBack { return .recallBothSides }
                    result = .recallFront
                }
            }

            return result
        }
    }

    @Model
    final class FlashcardTag {
        enum StoredStudyMode: UInt8, Codable {
            case recallFront, recallBoth, recallNeither
        }

        var name: String = "New tag"

        var rawStudyMode: StoredStudyMode?
        var flashcards: [Flashcard]?

        init() {}

        var studyMode: StudyMode? {
            switch rawStudyMode {
            case nil: .recallBack
            case .recallFront: .recallFront
            case .recallBoth: .recallBothSides
            case .recallNeither: nil
            }
        }
    }

    @Model
    final class FlashcardReview {
        enum Outcome: Int, Codable {
            case ok, fail, easy, hard
        }

        var flashcard: Flashcard?

        var date: Date = Date(timeIntervalSince1970: .zero)
        var outcome: Outcome = Outcome.ok

        init() {}
    }
}

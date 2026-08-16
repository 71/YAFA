@preconcurrency import FSRS
import Foundation
import Synchronization
import SwiftData
import os  // For `Logger`.

/// The current schema: terms connected by directed links, plus clozes.
///
/// The V1 models are deliberately absent. Listing them makes the store on disk already satisfy this
/// schema, so SwiftData sees nothing to migrate and the stage below never runs -- which is what
/// happened on device, where 855 flashcards sat next to zero terms. Leaving them out is what makes
/// the V1 -> V2 transition a migration at all.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Term.self, Link.self, Cloze.self, ClozeBlank.self, Progress.self, Review.self, Tag.self]
    }
}

let migrationLog = Logger(subsystem: "is.gregoirege.YAFA", category: "migration")

enum YAFAMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [migrateV1toV2] }

    /// The V1 data, read by `willMigrate` and written by `didMigrate`.
    ///
    /// A `Mutex` rather than a bare `static var`: the two halves are separate closures which
    /// SwiftData is free to call from whichever thread it likes, and the compiler cannot check that
    /// for us.
    private static let snapshotBox = Mutex<[MigratedFlashcard]>([])

    /// Turns each flashcard into two terms and one or two links.
    ///
    /// A flashcard studied in both directions becomes two links *sharing* one progress, rather than
    /// two independent ones: that preserves its scheduling exactly as it was, where one FSRS card
    /// and one review history backed a randomly-chosen direction per review.
    ///
    /// The work is split because it has to be: `willMigrate` runs while the store still speaks V1,
    /// and by the time `didMigrate` runs the V1 entities are gone. Reading happens in the first
    /// half, writing in the second, and the data crosses between them through ``snapshotBox`` as
    /// plain values -- no `@Model` survives, since its entity no longer exists.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            let flashcards = try context.fetch(FetchDescriptor<SchemaV1.Flashcard>())
            let snapshot = flashcards.compactMap(MigratedFlashcard.init)

            migrationLog.notice(
                """
                read \(flashcards.count, privacy: .public) flashcards, \
                \(snapshot.count, privacy: .public) of them non-empty
                """
            )

            snapshotBox.withLock { $0 = snapshot }
        },
        didMigrate: { context in
            let snapshot = snapshotBox.withLock { $0 }
            let existingTerms = try context.fetchCount(FetchDescriptor<Term>())

            migrationLog.notice(
                """
                writing: \(snapshot.count, privacy: .public) flashcards to convert, \
                \(existingTerms, privacy: .public) terms already present
                """
            )

            guard !snapshot.isEmpty else {
                migrationLog.notice("nothing to write: the snapshot is empty")
                return
            }

            // Terms already present means a previous attempt got partway and then stopped. Clearing
            // them makes this a retry rather than a doubling.
            if existingTerms > 0 {
                migrationLog.notice(
                    "found \(existingTerms, privacy: .public) terms from an earlier attempt; redoing"
                )

                for term in try context.fetch(FetchDescriptor<Term>()) {
                    context.delete(term)
                }
                for cloze in try context.fetch(FetchDescriptor<Cloze>()) {
                    context.delete(cloze)
                }
                for progress in try context.fetch(FetchDescriptor<Progress>()) {
                    context.delete(progress)
                }
                for tag in try context.fetch(FetchDescriptor<Tag>()) {
                    context.delete(tag)
                }

                try context.save()
            }

            var store = MigratedStore()

            for flashcard in snapshot {
                store.migrate(flashcard, in: context)
            }

            try context.save()

            let terms = try context.fetchCount(FetchDescriptor<Term>())
            let links = try context.fetchCount(FetchDescriptor<Link>())

            migrationLog.notice(
                """
                migrated \(snapshot.count, privacy: .public) flashcards into \
                \(terms, privacy: .public) terms and \(links, privacy: .public) links
                """
            )

            guard terms > 0 else {
                migrationLog.fault("migration produced no terms from \(snapshot.count) flashcards")

                assertionFailure("migration produced no terms from \(snapshot.count) flashcards")

                return
            }

            snapshotBox.withLock { $0 = [] }
        }
    )
}

/// Warns when the store still holds V1 flashcards after the container has opened.
///
/// The migration stage above is the mechanism; this is how we find out it did not run. On device
/// nothing was logged at all -- the stage was skipped in silence -- and an app which comes up empty
/// says nothing about why. Called once from `appModelContainer`.
@MainActor
func checkMigrationRan(in context: ModelContext) {
    do {
        let leftover = try context.fetchCount(FetchDescriptor<SchemaV1.Flashcard>())
        let terms = try context.fetchCount(FetchDescriptor<Term>())

        guard leftover > 0 else {
            migrationLog.notice("store holds \(terms, privacy: .public) terms, no V1 rows left")
            return
        }

        migrationLog.fault(
            """
            \(leftover, privacy: .public) V1 flashcards are still in the store alongside \
            \(terms, privacy: .public) terms: the migration stage did not run
            """
        )
    } catch {
        migrationLog.error(
            "could not check migration: \(error.localizedDescription, privacy: .public)"
        )
    }
}

/// A V1 flashcard, read out of the old store as plain values.
///
/// Every field is a copy: nothing here refers to a `@Model`, whose entity no longer exists by the
/// time `didMigrate` runs. The tags and reviews are named structs rather than tuples so that the
/// whole thing is `Sendable`, which is what lets it cross between the halves under a lock.
///
/// FSRS is imported `@preconcurrency` because its `Card` is a value type which predates `Sendable`
/// and has not been annotated.
struct MigratedFlashcard: Sendable {
    struct MigratedTag: Sendable {
        let name: String
        let isStudying: Bool
    }

    struct MigratedReview: Sendable {
        let date: Date
        let outcome: Review.Outcome
    }

    let front: String
    let back: String
    let notes: String
    let creationDate: Date
    let nextReviewDate: Date
    let fsrsCard: Card
    let studyMode: SchemaV1.StudyMode?
    let tags: [MigratedTag]
    let reviews: [MigratedReview]

    init?(_ flashcard: SchemaV1.Flashcard) {
        guard !flashcard.front.isEmpty || !flashcard.back.isEmpty else { return nil }

        front = flashcard.front
        back = flashcard.back
        notes = flashcard.notes
        creationDate = flashcard.creationDate
        nextReviewDate = flashcard.nextReviewDate
        fsrsCard = flashcard.fsrsCard
        studyMode = flashcard.studyMode
        tags = (flashcard.tags ?? []).map { .init(name: $0.name, isStudying: $0.studyMode != nil) }
        reviews = (flashcard.reviews ?? [])
            .sorted { $0.date < $1.date }
            .map { .init(date: $0.date, outcome: $0.outcome.migrated) }
    }
}

/// Accumulates the models created while migrating away from flashcards.
private struct MigratedStore {
    var tags: [String: Tag] = [:]
    var terms: [String: Term] = [:]

    mutating func migrate(_ flashcard: MigratedFlashcard, in context: ModelContext) {
        let tags = flashcard.tags.map { tag(named: $0.name, isStudying: $0.isStudying, in: context) }
        let front = term(
            text: flashcard.front,
            notes: flashcard.notes,
            creationDate: flashcard.creationDate,
            tags: tags,
            in: context
        )
        let back = term(
            text: flashcard.back,
            creationDate: flashcard.creationDate,
            tags: tags,
            in: context
        )

        let progress = Progress(creationDate: flashcard.creationDate)

        progress.fsrsCard = flashcard.fsrsCard
        progress.nextReviewDate = flashcard.nextReviewDate

        context.insert(progress)

        // A flashcard whose tags do not enable studying still becomes a link -- the direction it
        // would be studied in if its tags were re-enabled -- since tags no longer carry a
        // direction.
        let link: Link
        switch flashcard.studyMode {
        case .recallFront:
            link = self.link(from: back, to: front, of: flashcard, in: context, progress: progress)
        case .recallBothSides:
            link = self.link(from: front, to: back, of: flashcard, in: context, progress: progress)
            _ = self.link(from: back, to: front, of: flashcard, in: context, progress: progress)
        case nil, .recallBack:
            link = self.link(from: front, to: back, of: flashcard, in: context, progress: progress)
        }

        for oldReview in flashcard.reviews {
            // Every migrated review predates sharing, so we can only attribute it to one link. The
            // forward one is as good a guess as any, and matches what the card showed by default.
            progress.record(
                review: oldReview.date,
                outcome: oldReview.outcome,
                of: link,
                in: context
            )
        }
    }

    /// Returns the tag with the given name, creating it if this is the first time it is seen.
    ///
    /// A tag studied by any of the flashcards naming it is studied, full stop. In V1 the flag lived
    /// on the tag itself, so every flashcard reports the same value and the question never arises --
    /// but deciding it by whichever flashcard happened to come first would be luck rather than
    /// intent.
    private mutating func tag(named name: String, isStudying: Bool, in context: ModelContext) -> Tag {
        if let existing = tags[name] {
            existing.isStudying = existing.isStudying || isStudying

            return existing
        }

        let tag = Tag(name: name, isStudying: isStudying)

        tags[name] = tag
        context.insert(tag)

        return tag
    }

    /// Returns the term with the given text, creating it if this is the first time it is seen.
    ///
    /// Reusing terms across flashcards is what turns duplicated fronts and backs -- today's only
    /// way to write synonyms and homographs -- into a graph.
    private mutating func term(
        text: String,
        notes: String = "",
        creationDate: Date,
        tags: [Tag],
        in context: ModelContext
    ) -> Term {
        if let existing = terms[text] {
            for tag in tags where !existing.has(tag: tag) {
                existing.add(tag: tag)
            }
            if existing.notes.isEmpty {
                existing.notes = notes
            }
            return existing
        }

        let term = Term(text: text, notes: notes, creationDate: creationDate, tags: tags)

        terms[text] = term
        context.insert(term)

        return term
    }

    private func link(
        from source: Term,
        to target: Term,
        of flashcard: MigratedFlashcard,
        in context: ModelContext,
        progress: Progress
    ) -> Link {
        let link = Link(
            source: source,
            target: target,
            progress: progress,
            creationDate: flashcard.creationDate
        )

        context.insert(link)

        return link
    }
}

extension SchemaV1.FlashcardReview.Outcome {
    fileprivate var migrated: Review.Outcome {
        switch self {
        case .ok: .ok
        case .fail: .fail
        case .easy: .easy
        case .hard: .hard
        }
    }
}

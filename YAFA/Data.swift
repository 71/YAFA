import CoreData  // For CloudKit configuration.
import FSRS
import Foundation
import SwiftData
import os  // For `Logger`.

let appModels: [any PersistentModel.Type] = [
    Flashcard.self,
    FlashcardReview.self,
    FlashcardTag.self,
]

// Note: All attributes must either be optional or have default values for CloudKit integration.
//       Similarly, relationships must be optional and have explicit inverses.
@Model
final class Flashcard {
    var front: String = ""
    var back: String = ""

    private(set) var creationDate: Date = Date(timeIntervalSince1970: .zero)
    private(set) var modificationDate: Date = Date(timeIntervalSince1970: .zero)
    var nextReviewDate: Date = Date(timeIntervalSince1970: .zero)

    var fsrsCard: Card = Card()

    // We need an inverse relationship to preserve the many-to-many mapping.
    @Relationship(inverse: \FlashcardTag.flashcards)
    private(set) var tags: [FlashcardTag]?
    @Relationship(deleteRule: .cascade, inverse: \FlashcardReview.flashcard)
    private(set) var reviews: [FlashcardReview]?

    var lastReviewDate: Date? {
        reviews?.last?.date
    }
    var isEmpty: Bool {
        front.isEmpty && back.isEmpty && tags?.isEmpty != false
    }

    init(front: String = "", back: String = "", creationDate: Date = .now, tags: [FlashcardTag] = []) {
        self.front = front
        self.back = back
        self.creationDate = creationDate
        self.modificationDate = creationDate
        self.nextReviewDate = creationDate
        self.fsrsCard = .init(due: creationDate)
        self.tags = tags
        self.reviews = []
    }

    func addReview(outcome: FlashcardReview.Outcome) -> FlashcardReviewUndo {
        let now = Date.now
        let review = FlashcardReview(flashcard: self, date: now, outcome: outcome)

        if reviews == nil {
            reviews = [review]
        } else {
            reviews!.append(review)
        }

        let fsrs = FSRS(parameters: .init())
        let grade: Rating =
        switch outcome {
        case .ok:
                .good
        case .fail:
                .again
        }

        let undo = FlashcardReviewUndo(review: review, previousCard: fsrsCard, previousDue: nextReviewDate)

        fsrsCard = try! fsrs.next(card: fsrsCard, now: now, grade: grade).card
        nextReviewDate = fsrsCard.due

        return undo
    }

    fileprivate func undoReview(_ undo: FlashcardReviewUndo) {
        guard let flashcard = undo.review.flashcard else {
            return
        }
        guard let reviewIndex = flashcard.reviews?.lastIndex(of: undo.review) else {
            return
        }
        flashcard.reviews?.remove(at: reviewIndex)
        flashcard.nextReviewDate = undo.previousDue
        flashcard.fsrsCard = undo.previousCard
    }

    func has(tag: FlashcardTag) -> Bool {
        tags?.contains(tag) == true
    }

    func add(tag: FlashcardTag) {
        if tags == nil {
            tags = [tag]
        } else if !tags!.contains(tag) {
            tags!.append(tag)
        }
    }

    func remove(tag: FlashcardTag) {
        if let index = tags?.firstIndex(of: tag) {
            tags!.remove(at: index)
        }
    }

    func remove(tagOffsets: IndexSet) {
        tags?.remove(atOffsets: tagOffsets)
    }

    func insertIfNonEmpty(to modelContext: ModelContext) {
        if isEmpty {
            modelContext.delete(self)
        } else {
            modelContext.insert(self)
        }
    }
}

struct FlashcardReviewUndo {
    let review: FlashcardReview
    let previousCard: Card
    let previousDue: Date

    func undo() {
        self.review.flashcard?.undoReview(self)
    }
}

@Model
final class FlashcardTag {
    enum Selection: Int, Codable {
        case all, any, exclude
    }

    var name: String = "New tag"
    var selection: Selection?

    private(set) var flashcards: [Flashcard]?

    init(name: String) {
        self.name = name
    }
}

struct FlashcardTagsSelection: Equatable {
    private(set) var all: [FlashcardTag] = []
    private(set) var any: [FlashcardTag] = []
    private(set) var exclude: [FlashcardTag] = []

    var isEmpty: Bool {
        all.isEmpty && any.isEmpty && exclude.isEmpty
    }

    init(allTags: [FlashcardTag] = []) {
        for tag in allTags {
            switch tag.selection {
            case nil:
                break
            case .all:
                all.append(tag)
            case .any:
                any.append(tag)
            case .exclude:
                exclude.append(tag)
            }
        }
    }

    func contains(_ flashcard: Flashcard) -> Bool {
        guard let flashcardTags = flashcard.tags, !flashcardTags.isEmpty else {
            return all.isEmpty && any.isEmpty
        }

        for tag in exclude {
            if flashcard.has(tag: tag) {
                return false
            }
        }

        for tag in all {
            if !flashcard.has(tag: tag) {
                return false
            }
        }

        return any.isEmpty || any.contains { flashcard.has(tag: $0) }
    }
}

@Model
final class FlashcardReview {
    enum Outcome: Int, Codable, CustomStringConvertible {
        case ok, fail

        var description: String {
            switch self {
            case .ok: "ok"
            case .fail: "fail"
            }
        }
    }

    fileprivate var flashcard: Flashcard?

    private(set) var date: Date = Date(timeIntervalSince1970: .zero)
    private(set) var outcome: Outcome = Outcome.ok

    fileprivate init(flashcard: Flashcard, date: Date, outcome: Outcome) {
        self.flashcard = flashcard
        self.date = date
        self.outcome = outcome
    }
}

/// Creates a dummy `ModelContainer` used for previews.
@MainActor
internal func previewModelContainer() -> ModelContainer {
    let container = try! ModelContainer(
        for: Flashcard.self, FlashcardTag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    let flashcard = Flashcard(
        front: "한국어",
        back: "Korean language",
        tags: [FlashcardTag(name: "Vocabulary")]
    )
    _ = flashcard.addReview(outcome: .ok)

    container.mainContext.insert(flashcard)

    return container
}

/// Creates the `ModelContainer` used to store/load/synchronize app state.
@MainActor
internal func appModelContainer() -> ModelContainer {
    let schema = Schema(appModels)
    let config = ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .private(iCloudContainerIdentifier))

    if developmentMode {
        configureDevelopmentCloudKitContainer(config: config)
    }

    do {
        let modelContainer = try ModelContainer(
            for: schema, configurations: [config])
        modelContainer.mainContext.autosaveEnabled = true
        return modelContainer
    } catch {
        fatalError("could not create app ModelContainer: \(error)")
    }
}

private func configureDevelopmentCloudKitContainer(config: ModelConfiguration) {
    // https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices#Initialize-the-CloudKit-development-schema
    autoreleasepool {
        let description = NSPersistentStoreDescription(url: config.url)
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(
                containerIdentifier: iCloudContainerIdentifier)
        description.shouldAddStoreAsynchronously = false

        guard
            let managedObjectModel =
                NSManagedObjectModel.makeManagedObjectModel(for: appModels)
        else {
            fatalError("could not make development ManagedObjectModel")
        }

        let container = NSPersistentCloudKitContainer(
            name: "DevContainer", managedObjectModel: managedObjectModel)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                fatalError(
                    "could not load development CloudKit container: \(error)"
                )
            }
        }

        // Initialize the CloudKit schema after the store finishes loading.
        do {
            try container.initializeCloudKitSchema()
        } catch {
            fatalError(
                "could not initialize CloudKit schema: \(error)"
            )
        }

        // Remove and unload the store from the persistent container.
        if let store = container.persistentStoreCoordinator.persistentStores
            .first
        {
            do {
                try container.persistentStoreCoordinator.remove(store)
            } catch {
                Logger().warning(
                    "could not remove development store: \(error)"
                )
            }
        }
    }
}

private let iCloudContainerIdentifier = "iCloud.gregoirege.is.YAFA.Container"

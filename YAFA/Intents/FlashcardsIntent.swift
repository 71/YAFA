import AppIntents
import SwiftData
import SwiftUI

struct CountFlashcardsIntent: AppIntent {
    static var title: LocalizedStringResource = "Count pending flashcards"
    static var supportedModes: IntentModes = .background

    @Dependency var modelContainer: ModelContainer

    @Parameter(title: "Tags", description: "Tags to add to new flashcards.")
    var tags: [TagEntity]?

    @MainActor
    func perform() async throws -> some ReturnsValue<Int> {
        let tags = if let tags {
            Set(try TagEntity.resolve(tags, in: modelContainer))
        } else {
            Set<FlashcardTag>()
        }
        let now = Date()
        let fetchDescriptor = FetchDescriptor(
            predicate: #Predicate<Flashcard> { flashcard in
                flashcard.nextReviewDate <= now
            }
        )
        let count = if tags.isEmpty {
            try modelContainer.mainContext.fetchCount(fetchDescriptor)
        } else {
            try modelContainer.mainContext.fetch(fetchDescriptor).count { flashcard in
                flashcard.has(tagIn: tags)
            }
        }
        return .result(value: count)
    }
}

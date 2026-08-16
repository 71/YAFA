import AppIntents
import SwiftData
import SwiftUI

/// Note: the type name is part of the intent's persistent identity, so it keeps its old
/// "flashcards" spelling to avoid breaking shortcuts users have already built on it.
struct CountFlashcardsIntent: AppIntent {
    static var title: LocalizedStringResource = "Count pending reviews"
    static var supportedModes: IntentModes = .background

    @Dependency var modelContainer: ModelContainer

    @Parameter(title: "Tags", description: "Only count reviews of terms with these tags.")
    var tags: [TagEntity]?

    @MainActor
    func perform() async throws -> some ReturnsValue<Int> {
        let tags = if let tags {
            Set(try TagEntity.resolve(tags, in: modelContainer))
        } else {
            Set<Tag>()
        }
        let now = Date()
        let duePasses = try modelContainer.mainContext.fetch(
            FetchDescriptor(
                predicate: #Predicate<Progress> { progress in
                    progress.nextReviewDate <= now
                }
            )
        )

        // A progress shared by several links or blanks is one pending review, not several: studying
        // any of them schedules them all.
        let count = duePasses.count { progress in
            guard !tags.isEmpty else { return true }

            return progress.sharers.contains { $0.owningTerm?.has(tagIn: tags) == true }
        }

        return .result(value: count)
    }
}

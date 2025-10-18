import AppIntents
import SwiftData
import SwiftUI

@MainActor
@Observable
class NavigationModel {
    struct ImportParameters: Hashable {
        let text: String
        let tags: [FlashcardTag]
    }

    var importParameters: ImportParameters?
}

struct ImportIntent: AppIntent {
    static var title: LocalizedStringResource = "Import flashcards"
    static var supportedModes: IntentModes = .foreground(.immediate)

    @Dependency var modelContainer: ModelContainer
    @Dependency var navigationModel: NavigationModel

    @Parameter(
        title: "Text",
        description: "Import text",
        inputOptions: .init(multiline: true, smartQuotes: false, smartDashes: false)
    )
    var text: String

    @Parameter(title: "Tags", description: "Tags to add to new flashcards.")
    var tags: [TagEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        let tags = try TagEntity.resolve(tags, in: modelContainer)

        navigationModel.importParameters = .init(text: text, tags: tags)

        return .result()
    }
}

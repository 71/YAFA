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
        let tagIds = Set(
            try tags.map {
                try JSONDecoder().decode(PersistentIdentifier.self, from: $0.id.data(using: .utf8)!)
            }
        )
        let tags = try modelContainer.mainContext.fetch(
            .init(
                predicate: #Predicate<FlashcardTag> {
                    tagIds.contains($0.persistentModelID)
                }
            )
        )

        navigationModel.importParameters = .init(text: text, tags: tags)

        return .result()
    }
}

struct TagEntity: AppEntity {
    typealias ID = String

    struct Query: EntityQuery {
        @Dependency var modelContainer: ModelContainer

        @MainActor
        func entities(for identifiers: [ID]) async throws -> [TagEntity] {
            let tags = try modelContainer.mainContext.fetch(
                .init(predicate: Predicate<FlashcardTag>.true)
            )
            let tagsById = Dictionary(uniqueKeysWithValues: tags.map { ($0.idString, $0) })

            return identifiers.compactMap {
                guard let tag = tagsById[$0] else { return nil }

                return .init(tag)
            }
        }

        @MainActor
        func entities(matching string: String) async throws -> [TagEntity] {
            let tags = try modelContainer.mainContext.fetch(
                .init(predicate: Predicate<FlashcardTag>.true)
            )
            let search = SearchDictionary(tags, by: \.name)

            return search.including(string).sorted(by: { a, b in
                a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }).map { .init($0) }
        }

        @MainActor
        func suggestedEntities() async throws -> [TagEntity] {
            let tags = try modelContainer.mainContext.fetch(
                .init(predicate: Predicate<FlashcardTag>.true)
            )

            return tags.map { .init($0) }
        }
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(
        name: "Tag",
        numericFormat: LocalizedStringResource("\(placeholder: .int) tags")
    )
    static var defaultQuery: Query { .init() }

    let id: ID
    private let name: String
    private let flashcards: Int

    init(_ tag: FlashcardTag) {
        id = tag.idString
        name = tag.name
        flashcards = tag.flashcards?.count ?? 0
    }

    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)", subtitle: "\(flashcards) flashcard\(flashcards == 1 ? "" : "s")")
    }
}

extension FlashcardTag {
    fileprivate var idString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return .init(data: try! encoder.encode(persistentModelID), encoding: .utf8)!
    }
}

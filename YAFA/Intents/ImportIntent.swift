import AppIntents
import SwiftData
import SwiftUI

@MainActor
@Observable
class NavigationModel {
    struct ImportParameters: Hashable {
        var text: String
        var tags: [Tag]
    }

    struct AddParameters: Hashable {
        var front: String
        var back: String
        var tags: [Tag]
        var notes: String
    }

    struct SearchParameters: Hashable {
        var search: String
        var tags: [Tag]
    }

    enum Parameters: Hashable {
        case import_(ImportParameters)
        case add(AddParameters)
        case search(SearchParameters)
    }

    var parameters: Parameters?

    var importParameters: ImportParameters? {
        get {
            if case .import_(let params) = parameters {
                params
            } else {
                nil
            }
        }
        set {
            parameters = newValue.map { .import_($0) }
        }
    }

    var addParameters: AddParameters? {
        get {
            if case .add(let params) = parameters {
                params
            } else {
                nil
            }
        }
        set {
            parameters = newValue.map { .add($0) }
        }
    }

    var searchParameters: SearchParameters? {
        get {
            if case .search(let params) = parameters {
                params
            } else {
                nil
            }
        }
        set {
            parameters = newValue.map { .search($0) }
        }
    }
}

struct ImportIntent: AppIntent {
    static var title: LocalizedStringResource = "Import terms"
    static var supportedModes: IntentModes = .foreground(.immediate)

    @Dependency var modelContainer: ModelContainer
    @Dependency var navigationModel: NavigationModel

    @Parameter(
        title: "Text",
        description: "Import text",
        inputOptions: .init(multiline: true, smartQuotes: false, smartDashes: false)
    )
    var text: String

    @Parameter(title: "Tags", description: "Tags to add to new terms.")
    var tags: [TagEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        let tags = try TagEntity.resolve(tags, in: modelContainer)

        navigationModel.importParameters = .init(text: text, tags: tags)

        return .result()
    }
}

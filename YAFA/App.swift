import AppIntents
import SwiftUI

@main
struct YAFAApp: App {
    #if targetEnvironment(simulator)
        var sharedModelContainer = previewModelContainer()
    #else
        var sharedModelContainer = appModelContainer()
    #endif

    @State var navigationModel: NavigationModel = .init()
    @State var navigationError: (any Error)?

    init() {
        let modelContainer = self.sharedModelContainer
        let navigationModel = self.navigationModel

        AppDependencyManager.shared.add(dependency: navigationModel)
        AppDependencyManager.shared.add(dependency: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView(navigationModel: navigationModel)
                .onOpenURL {
                    do {
                        try handle(url: $0)
                    } catch {
                        self.navigationError = error
                    }
                }
                .alert(
                    self.navigationError?.localizedDescription ?? "",
                    isPresented: Binding(
                        get: { self.navigationError != nil },
                        set: { show in if !show { self.navigationError = nil } },
                    ),
                    actions: {}
                )
        }
        .modelContainer(sharedModelContainer)
    }

    private func handle(url: URL) throws {
        // Parse query parameters.
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let parameters = components.queryItems
        else {
            throw UrlHandlingError(url: url, message: "invalid URL format")
        }

        switch components.path {
        case "add": try handleAdd(url: url, parameters)
        case "search": try handleSearch(url: url, parameters)
        case let unknown: throw UrlHandlingError(url: url, message: "unknown request \"\(unknown)\"")
        }
    }

    private func handleAdd(url: URL, _ parameters: [URLQueryItem]) throws {
        var front: String?
        var back: String?
        var notes: String = ""
        var tags: [FlashcardTag] = []

        for param in parameters {
            switch param.name {
            case "front":
                guard let value = param.value else {
                    throw UrlHandlingError(url: url, message: "missing front text")
                }
                front = value
            case "back":
                guard let value = param.value else {
                    throw UrlHandlingError(url: url, message: "missing back text")
                }
                back = value
            case "notes":
                guard let value = param.value else {
                    throw UrlHandlingError(url: url, message: "missing notes text")
                }
                notes = value
            case "tag", "tags":
                tags.append(try parseQueryTag(url: url, param))

            case let unknown:
                throw UrlHandlingError(url: url, message: "unknown parameter \"\(unknown)\"")
            }
        }

        guard let front else { throw UrlHandlingError(url: url, message: "missing front text") }
        guard let back else { throw UrlHandlingError(url: url, message: "missing back text") }

        navigationModel.parameters = .add(.init(front: front, back: back, tags: tags, notes: notes))
    }

    private func handleSearch(url: URL, _ parameters: [URLQueryItem]) throws {
        var search: String = ""
        var tags: [FlashcardTag] = []

        for param in parameters {
            switch param.name {
            case "q":
                search = param.value ?? ""
            case "tag", "tags":
                tags.append(try parseQueryTag(url: url, param))

            case let unknown:
                throw UrlHandlingError(url: url, message: "unknown parameter \"\(unknown)\"")
            }
        }

        navigationModel.parameters = .search(.init(search: search, tags: tags))
    }

    private func parseQueryTag(url: URL, _ item: URLQueryItem) throws -> FlashcardTag {
        guard let value = item.value else {
            throw UrlHandlingError(url: url, message: "missing tag text")
        }
        let matchingTags = try sharedModelContainer.mainContext.fetch(
            .init(predicate: #Predicate<FlashcardTag> { $0.name == value })
        )
        guard let tag = matchingTags.first else {
            throw UrlHandlingError(url: url, message: "unknown tag \"\(value)\"")
        }
        guard matchingTags.count == 1 else {
            throw UrlHandlingError(
                url: url,
                message: "more than one tag called \"\(value)\""
            )
        }
        return tag
    }
}

#if DEBUG
    let developmentMode = true
#else
    let developmentMode = false
#endif

private struct UrlHandlingError: LocalizedError {
    let url: URL
    let message: String

    var errorDescription: String? { "Cannot open \(url): \(message)" }
}

import CoreData  // For CloudKit configuration.
import Foundation
import SwiftData
import os  // For `Logger`.

let appModels: [any PersistentModel.Type] = SchemaV2.models

/// Creates a dummy `ModelContainer` used for previews.
@MainActor
internal func previewModelContainer() -> ModelContainer {
    let container = try! ModelContainer(
        for: Schema(appModels),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let vocabulary = Tag(name: "Vocabulary")

    context.insert(vocabulary)
    context.insert(Tag(name: "Not studying", isStudying: false))

    /// Inserts `source` and `target` as terms, linked in the given direction(s).
    @discardableResult
    func add(_ text: String, _ definition: String, bothWays: Bool = false) -> (Term, Term) {
        let term = Term(text: text, tags: [vocabulary])
        let definitionTerm = Term(text: definition, tags: [vocabulary])

        context.insert(term)
        context.insert(definitionTerm)

        let link = Link(source: term, target: definitionTerm)

        context.insert(link)

        if bothWays {
            // Share one progress so that studying either direction schedules both.
            context.insert(Link(source: definitionTerm, target: term, progress: link.progress))
        }

        return (term, definitionTerm)
    }

    let (korean, _) = add("한국어", "Korean language")

    korean.outgoingLinks?.first?.addReview(outcome: .ok)

    for (ko, en) in [
        ("하나", "one"),
        ("둘", "two"),
        ("셋", "three"),
        ("넷", "four"),
        ("다섯", "five"),
        ("여섯", "six"),
    ] {
        add(ko, en, bothWays: ko == "하나")
    }

    // A homograph: one term, two outgoing links.
    let tea = Term(text: "tea", tags: [vocabulary])
    let car = Term(text: "car", tags: [vocabulary])
    let cha = Term(text: "차", tags: [vocabulary])

    context.insert(tea)
    context.insert(car)
    context.insert(cha)
    context.insert(Link(source: cha, target: tea))
    context.insert(Link(source: cha, target: car))

    // Synonyms: two terms pointing at one, sharing its progress so that recalling either counts.
    let big = Term(text: "big", tags: [vocabulary])
    let large = Term(text: "large", tags: [vocabulary])
    let keun = Term(text: "큰", tags: [vocabulary])

    context.insert(big)
    context.insert(large)
    context.insert(keun)

    let bigLink = Link(source: big, target: keun)

    context.insert(bigLink)
    context.insert(Link(source: large, target: keun, progress: bigLink.progress))

    bigLink.addReview(outcome: .ok)

    // A cloze: one sentence, one blank, answered by a term which is also studied on its own.
    let school = Term(text: "학교", tags: [vocabulary])
    let template = "고양이가 학교에 갔다"
    let cloze = Cloze(template: template, tags: [vocabulary])

    let schoolEn = Term(text: "school", tags: [vocabulary])

    context.insert(school)
    context.insert(schoolEn)
    context.insert(cloze)
    context.insert(Link(source: school, target: schoolEn))

    if let range = template.range(of: "학교") {
        cloze.addBlank(term: school, ranges: [range])
    }

    // One term with several links, two of which share a progress, so the links list has both a
    // shared group and standalone rows.
    let mek = Term(text: "먹다", tags: [vocabulary])
    let toEat = Term(text: "to eat", tags: [vocabulary])
    let toConsume = Term(text: "to consume", tags: [vocabulary])
    let toDrink = Term(text: "to drink", tags: [vocabulary])

    for term in [mek, toEat, toConsume, toDrink] {
        context.insert(term)
    }

    let eatLink = Link(source: mek, target: toEat)

    context.insert(eatLink)
    context.insert(Link(source: mek, target: toConsume, progress: eatLink.progress))
    context.insert(Link(source: mek, target: toDrink))

    // Unlinked terms: nothing points at them and nothing is studied from them, so they show up in
    // the "Unlinked" section as work still to finish.
    context.insert(Term(text: "Unfinished", tags: [vocabulary]))
    context.insert(Term(text: "덤"))

    add("Example", "Longer sentence used to make sure the text wraps correctly.")

    return container
}

/// Returns the term with the given text from a preview container, for previews which need a
/// specific shape (a homograph, a synonym, a cloze) rather than any term at all.
@MainActor
internal func previewTerm(_ text: String, in container: ModelContainer) -> Term {
    try! container.mainContext.fetch(
        FetchDescriptor<Term>(predicate: #Predicate { $0.text == text })
    ).first!
}

/// Creates the `ModelContainer` used to store/load/synchronize app state.
@MainActor
internal func appModelContainer() -> ModelContainer {
    let schema = Schema(SchemaV2.models, version: SchemaV2.versionIdentifier)
    let config = ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .private(iCloudContainerIdentifier)
    )

    if developmentMode {
        // This prevents the code from running offline. Make sure that the build you're using is
        // not a debug build outside of testing.
        configureDevelopmentCloudKitContainer(config: config)
    }

    do {
        let modelContainer = try ModelContainer(
            for: schema,
            migrationPlan: YAFAMigrationPlan.self,
            configurations: [config]
        )

        modelContainer.mainContext.autosaveEnabled = true

        checkMigrationRan(in: modelContainer.mainContext)

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
                containerIdentifier: iCloudContainerIdentifier
            )
        description.shouldAddStoreAsynchronously = false

        guard
            let managedObjectModel =
                NSManagedObjectModel.makeManagedObjectModel(for: appModels)
        else {
            fatalError("could not make development ManagedObjectModel")
        }

        let container = NSPersistentCloudKitContainer(
            name: "DevContainer",
            managedObjectModel: managedObjectModel
        )
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
